import ProseEditor
import ProseModel
import SwiftYrs

/// Binds an `EditorCore` to a Yjs `YXmlFragment`, converging a single plain-text
/// paragraph (`doc > paragraph > text`) with a y-prosemirror peer.
///
/// This is slice 1 (the tracer bullet): no marks, no block variety.
@MainActor
public final class YBinding {
    /// y-prosemirror's default root name. Tiptap defaults to `"default"`; both
    /// peers MUST agree or they silently never converge (see `attach`).
    public static let defaultFragmentName = "prosemirror"

    private let core: EditorCore
    private let doc: YDoc
    private let fragment: YXmlFragment

    private let bindingOrigin = "prosekit-yjs-binding"

    private var observation: Observation?
    /// SwiftYrs has no deep observation, and a text change inside
    /// `paragraph > text` is a deep change the fragment observer never sees. We
    /// also observe the inner `YXmlText` directly; its branch identity is stable
    /// for the document's lifetime, so one observation suffices.
    private var textObservation: Observation?
    private var syncTask: Task<Void, Never>?

    /// True while we are writing our own change into Y. The fragment observer
    /// fires synchronously inside that write, so this guard breaks the loop.
    private var isApplyingLocalWrite = false

    /// Gates the encoder/decoder until the provider's first sync completes.
    private var hasJoined = false

    public init(core: EditorCore, doc: YDoc, fragmentName: String = defaultFragmentName) {
        precondition(!fragmentName.isEmpty, "fragmentName must be non-empty and match the peer's root name")
        self.core = core
        self.doc = doc
        guard let fragment = try? doc.xmlFragment(named: fragmentName) else {
            preconditionFailure("YDoc could not vend an XML fragment named \(fragmentName)")
        }
        self.fragment = fragment

        core.didApplyTransaction = { [weak self] applied in
            self?.handleLocalTransaction(applied)
        }
        observation = try? fragment.observe { event in
            guard case .shared = event else { return }
            // The observer fires synchronously inside a MainActor-confined
            // write/apply, so we are already on the MainActor here. We cannot
            // open a read transaction here (the apply's write txn is still live),
            // so we only (re)bind the inner text observation; its delta carries
            // the actual text change.
            MainActor.assumeIsolated { [weak self] in
                self?.ensureTextObservation()
            }
        }
    }

    /// Observes the inner text node once it exists (it may be created by a local
    /// edit or arrive in a remote update). Idempotent.
    private func ensureTextObservation() {
        guard textObservation == nil, let textNode = currentTextNode() else { return }
        textObservation = try? textNode.observe { event in
            guard case let .shared(shared) = event else { return }
            MainActor.assumeIsolated { [weak self] in
                self?.handleTextDelta(shared.delta)
            }
        }
    }

    /// Drives the Join gate off the provider's `synced` signal: on the first
    /// `true`, reconcile the `Document` and the replica, then go live.
    public func attach(syncedSignal: AsyncStream<Bool>) {
        syncTask = Task { @MainActor [weak self] in
            for await synced in syncedSignal where synced {
                self?.join()
                break
            }
        }
    }

    public func detach() {
        syncTask?.cancel()
        syncTask = nil
        observation = nil
        textObservation = nil
        core.didApplyTransaction = nil
        hasJoined = false
    }

    /// The Join reconcile (idempotent): an empty replica is seeded from the local
    /// `Document`; a non-empty replica replaces the local `Document` (`.remote`,
    /// no history). Exposed for tests that drive the gate without a provider.
    func join() {
        guard !hasJoined else { return }
        hasJoined = true
        let replicaText = currentReplicaText()
        if replicaText.isEmpty {
            encodeToReplica(core.document.plainText)
        } else {
            applyRemoteText(replicaText)
        }
        ensureTextObservation()
    }

    // MARK: - Encoder (PM → Y)

    private func handleLocalTransaction(_ applied: AppliedTransaction) {
        // A remote apply already matches the replica; re-encoding it would echo.
        guard hasJoined, applied.origin != .remote else { return }
        encodeToReplica(applied.document.plainText)
    }

    private func encodeToReplica(_ text: String) {
        isApplyingLocalWrite = true
        defer { isApplyingLocalWrite = false }
        try? doc.write(origin: bindingOrigin) { transaction in
            let paragraph = try paragraphElement(in: transaction)
            let textNode = try editableTextNode(in: paragraph, transaction: transaction)
            let current = try transaction.string(from: textNode)
            let diff = TextDiff(from: current, to: text)
            guard diff.hasChange else { return }
            if diff.removedLength > 0 {
                try transaction.remove(from: textNode, at: UInt32(diff.prefix), length: UInt32(diff.removedLength))
            }
            if !diff.inserted.isEmpty {
                try transaction.insert(diff.inserted, into: textNode, at: UInt32(diff.prefix))
            }
        }
        ensureTextObservation()
    }

    private func paragraphElement(in transaction: YWriteTransaction) throws -> YXmlElement {
        if try transaction.childCount(of: fragment) > 0,
           case let .element(element) = try transaction.child(at: 0, in: fragment) {
            return element
        }
        return try transaction.insertElement(named: "paragraph", into: fragment, at: 0)
    }

    private func editableTextNode(in paragraph: YXmlElement, transaction: YWriteTransaction) throws -> YXmlText {
        if try transaction.childCount(of: paragraph) > 0,
           case let .text(textNode) = try transaction.child(at: 0, in: paragraph) {
            return textNode
        }
        return try transaction.insertText(into: paragraph, at: 0)
    }

    // MARK: - Decoder (Y → PM)

    /// Translates a remote `YXmlText` delta into a `.remote` ProseKit
    /// transaction, carrying the local selection across the change.
    private func handleTextDelta(_ delta: [YTextDeltaOperation]) {
        guard hasJoined, !isApplyingLocalWrite else { return }

        var cursor = textBasePosition
        var steps: [any Step] = []
        for op in delta {
            switch op {
            case let .retain(length, _):
                cursor += Int(length)
            case let .insert(value, _):
                guard case let .string(string) = value, !string.isEmpty else { continue }
                steps.append(ReplaceStep(from: cursor, to: cursor, insertText: string))
                cursor += string.count
            case let .delete(length):
                steps.append(ReplaceStep(from: cursor, to: cursor + Int(length), insertText: ""))
            }
        }
        applyRemoteSteps(steps)
    }

    /// Reconciles the local `Document` to `replicaText` via a `.remote`
    /// transaction. Used by the Join gate, which runs outside an observer and so
    /// may read the replica.
    private func applyRemoteText(_ replicaText: String) {
        let base = textBasePosition
        let diff = TextDiff(from: core.document.plainText, to: replicaText)
        guard diff.hasChange else { return }
        applyRemoteSteps([ReplaceStep(
            from: base + diff.prefix,
            to: base + diff.prefix + diff.removedLength,
            insertText: diff.inserted
        )])
    }

    private func applyRemoteSteps(_ steps: [any Step]) {
        guard !steps.isEmpty else { return }
        let mapping = Mapping(steps)
        let mappedSelection = core.selection.mapped(through: mapping)
        core.applyRemote(Transaction(steps: steps, selection: mappedSelection, origin: .remote))
    }

    /// The Position of the first text character in the single paragraph. For a
    /// flat single-paragraph document this is the paragraph's open token + 1.
    private var textBasePosition: Position {
        core.document.endTextPosition - core.document.totalTextCount
    }

    private func currentReplicaText() -> String {
        (try? doc.read { transaction -> String in
            guard let textNode = try currentTextNode(in: transaction) else { return "" }
            return try transaction.string(from: textNode)
        }) ?? ""
    }

    private func currentTextNode() -> YXmlText? {
        (try? doc.read { transaction in
            try currentTextNode(in: transaction)
        }) ?? nil
    }

    private func currentTextNode(in transaction: YReadTransaction) throws -> YXmlText? {
        guard try transaction.childCount(of: fragment) > 0,
              case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
              try transaction.childCount(of: paragraph) > 0,
              case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
        else { return nil }
        return textNode
    }
}

/// A minimal common prefix/suffix text diff. Indices are in `Character`s, which
/// equals UTF-16 code units for the BMP (sufficient for the plain-text tracer;
/// non-BMP handling is a later-slice concern).
private struct TextDiff {
    let prefix: Int
    let removedLength: Int
    let inserted: String

    init(from old: String, to new: String) {
        let oldChars = Array(old)
        let newChars = Array(new)

        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldChars.count - prefix,
              suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        self.prefix = prefix
        self.removedLength = oldChars.count - prefix - suffix
        self.inserted = String(newChars[prefix..<(newChars.count - suffix)])
    }

    var hasChange: Bool {
        removedLength > 0 || !inserted.isEmpty
    }
}
