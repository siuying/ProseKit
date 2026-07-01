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

        // The same awareness shape tiptap's CollaborationCursor publishes:
        // user + cursor (anchor/head as y-prosemirror relative positions).
        publishPresence()
        // Selection changes republish the cursor; edits (which also fire this)
        // additionally re-resolve remote cursors against the moved text.
        proseView.core.didChangeSelection = { [weak self] _ in
            self?.publishPresence()
            self?.refreshRemoteSelections()
        }
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
                    self?.refreshRemoteSelections()
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
        var state: [String: Any] = ["user": ["name": localName, "color": localColor]]
        if let cursor = cursorPayload() {
            state["cursor"] = cursor
        }
        try? editorAwareness.setLocalState(state)
    }

    /// The local Selection as y-prosemirror's awareness cursor shape:
    /// `{ anchor: <relative position JSON>, head: <relative position JSON> }`.
    private func cursorPayload() -> [String: Any]? {
        let selection = proseView.core.selection
        guard let anchor = binding.relativePosition(for: selection.anchor),
              let head = binding.relativePosition(for: selection.head),
              let anchorJSON = try? JSONSerialization.jsonObject(with: anchor.json),
              let headJSON = try? JSONSerialization.jsonObject(with: head.json)
        else { return nil }
        return ["anchor": anchorJSON, "head": headJSON]
    }

    /// Re-resolves every peer's published cursor against the current replica
    /// and hands the result to the view's remote-selection chrome.
    private func refreshRemoteSelections() {
        let localID = editorAwareness.clientID
        let states = (try? editorAwareness.states()) ?? []
        proseView.remoteSelections = states.compactMap { entry -> RemoteSelection? in
            guard entry.clientID != localID,
                  let state = entry.state as? [String: Any],
                  let user = state["user"] as? [String: Any],
                  let name = user["name"] as? String,
                  let cursor = state["cursor"] as? [String: Any],
                  let anchor = position(fromCursorField: cursor["anchor"]),
                  let head = position(fromCursorField: cursor["head"])
            else { return nil }
            return RemoteSelection(
                id: entry.clientID,
                name: name,
                color: PlatformColor(hex: user["color"] as? String ?? "#888888"),
                selection: TextSelection(anchor: anchor, head: head)
            )
        }
    }

    private func position(fromCursorField field: Any?) -> Position? {
        guard let field,
              JSONSerialization.isValidJSONObject(field),
              let data = try? JSONSerialization.data(withJSONObject: field),
              let relative = try? YRelativePosition(json: data)
        else { return nil }
        return binding.position(for: relative)
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

extension PlatformColor {
    /// Parses the "#rrggbb" colors peers publish in their awareness user field.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0))).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
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
