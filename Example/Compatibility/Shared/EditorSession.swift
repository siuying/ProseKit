import Foundation
import ProseEditor
import ProseKitYjs
import ProseModel
import SwiftYrs
import SwiftYrsHocuspocus

struct Participant: Identifiable, Equatable {
    let id: UInt64
    let name: String
    let color: String
    let isLocal: Bool
}

/// Owns the whole collaboration stack for one editor.
///
/// Two YDoc replicas, not one: a YDoc handle must have a single serialization
/// owner, but `YBinding` requires the editor's MainActor while
/// `HocuspocusProvider` reads and writes its document on its own actor.
/// Sharing one doc crashes the moment a remote update lands (the binding's
/// observers assert MainActor from the provider's executor). So the editor
/// binds to a MainActor-owned replica, the provider syncs its own
/// network-side replica, and this session forwards update bytes between them
/// on the owning executor of each. Echoes terminate because applying an
/// already-known Yjs update changes nothing and emits no update event.
/// Awareness is bridged the same way.
@MainActor
final class EditorSession: ObservableObject {
    // Must match the web demo: same room, and YBinding's default fragment
    // name ("prosemirror") matches the tiptap Collaboration `field`.
    static let serverURL = URL(string: "ws://localhost:4321/collaboration")!
    static let documentName = "prosekit-compatibility"

    let proseView: ProseView
    let localName: String
    let localColor: String

    @Published private(set) var participants: [Participant] = []
    @Published private(set) var status: ConnectionStatus = .connecting

    // Editor side — MainActor is the serialization owner.
    private let editorDoc: YDoc
    private let editorAwareness: YAwareness
    private let binding: YBinding

    // Network side — the provider's actor is the serialization owner after
    // connect(); this class only touches these via provider-isolated methods.
    private let networkDoc: YDoc
    private let networkAwareness: YAwareness
    private let provider: HocuspocusProvider

    private var observations: [Observation] = []
    private var tasks: [Task<Void, Never>] = []

    init() {
        proseView = ProseView(document: Document(.doc([.paragraph([])])))
        editorDoc = ProseKitYjs.makeDocument()
        editorAwareness = YAwareness(document: editorDoc)
        binding = YBinding(core: proseView.core, doc: editorDoc)

        networkDoc = YDoc()
        networkAwareness = YAwareness(document: networkDoc)
        provider = HocuspocusProvider(
            url: Self.serverURL,
            name: Self.documentName,
            document: networkDoc,
            awareness: networkAwareness
        )

        #if os(macOS)
        let platform = "Mac"
        #else
        let platform = "iOS"
        #endif
        let names = [
            "Ada", "Grace", "Alan", "Edsger", "Barbara", "Donald",
            "Margaret", "Dennis", "Radia", "Linus", "Katherine", "Bjarne",
        ]
        let colors = [
            "#e11d48", "#ea580c", "#ca8a04", "#16a34a", "#0d9488",
            "#2563eb", "#7c3aed", "#c026d3",
        ]
        localName = "\(names.randomElement()!) (\(platform))"
        localColor = colors.randomElement()!

        startBridging()

        // The same awareness shape tiptap's CollaborationCursor publishes;
        // without a `cursor` field web peers list us but draw no caret.
        publishPresence()
        // Peers prune awareness states not renewed within ~30s (y-protocols
        // outdatedTimeout). The JS provider re-broadcasts on a timer; renew
        // presence ourselves.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.publishPresence()
            }
        })

        binding.attach(syncedSignal: provider.isSynced)

        let statusStream = provider.connectionStatus
        tasks.append(Task { [weak self] in
            for await status in statusStream {
                self?.status = status
            }
        })
        if let changes = try? editorAwareness.changeEvents() {
            tasks.append(Task { [weak self] in
                for await _ in changes {
                    self?.refreshParticipants()
                }
            })
        }
        refreshParticipants()

        let provider = provider
        tasks.append(Task {
            try? await provider.connect()
        })
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    /// Registers the four forwarding observers. Runs in init, before
    /// connect(), so registration itself races with nothing.
    private func startBridging() {
        let provider = provider
        let networkDoc = networkDoc
        let networkAwareness = networkAwareness
        let editorDoc = editorDoc
        let editorAwareness = editorAwareness

        // Editor -> network. Fires on MainActor (only this actor writes
        // editorDoc); the apply hops to the provider's executor.
        if let observation = try? editorDoc.observeUpdates({ event in
            guard case let .update(update) = event else { return }
            Task { await provider.bridgeApply(update, to: networkDoc) }
        }) {
            observations.append(observation)
        }

        // Network -> editor. Fires on the provider's executor when a remote
        // update (or a forwarded local one, then a no-op) is applied.
        if let observation = try? networkDoc.observeUpdates({ event in
            guard case let .update(update) = event else { return }
            Task { @MainActor in try? editorDoc.apply(update) }
        }) {
            observations.append(observation)
        }

        // Same in both directions for awareness. encodeUpdate must run on
        // the thread that committed the change, i.e. inside the callback.
        if let observation = try? editorAwareness.observeUpdate({ event in
            guard case let .awarenessUpdate(change) = event, !change.changed.isEmpty,
                  let update = try? editorAwareness.encodeUpdate(for: change.changed)
            else { return }
            Task { await provider.bridgeApply(update, to: networkAwareness) }
        }) {
            observations.append(observation)
        }

        if let observation = try? networkAwareness.observeUpdate({ event in
            guard case let .awarenessUpdate(change) = event, !change.changed.isEmpty,
                  let update = try? networkAwareness.encodeUpdate(for: change.changed)
            else { return }
            Task { @MainActor in try? editorAwareness.applyUpdate(update) }
        }) {
            observations.append(observation)
        }
    }

    private func publishPresence() {
        try? editorAwareness.setLocalState(
            ["user": ["name": localName, "color": localColor]]
        )
    }

    private func refreshParticipants() {
        let localID = editorAwareness.clientID
        let states = (try? editorAwareness.states()) ?? []
        participants = states
            .compactMap { entry -> Participant? in
                guard let state = entry.state as? [String: Any],
                      let user = state["user"] as? [String: Any],
                      let name = user["name"] as? String
                else { return nil }
                return Participant(
                    id: entry.clientID,
                    name: name,
                    color: user["color"] as? String ?? "#888888",
                    isLocal: entry.clientID == localID
                )
            }
            .sorted { $0.name < $1.name }
    }
}

extension HocuspocusProvider {
    /// Demo-side seam: these run isolated to the provider actor, so bridge
    /// applies serialize with the provider's own reads and writes of the
    /// network-side replicas.
    func bridgeApply(_ update: YUpdate, to doc: YDoc) {
        try? doc.apply(update)
    }

    func bridgeApply(_ update: YAwarenessUpdate, to awareness: YAwareness) {
        try? awareness.applyUpdate(update)
    }
}
