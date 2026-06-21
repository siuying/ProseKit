import Foundation
import ProseEditor
import ProseModel
import SwiftYrs

/// Binds an `EditorCore` to a Yjs `YXmlFragment`, converging a single textblock
/// (`doc > paragraph > text…`) with a y-prosemirror peer, including inline
/// **Marks** (slice 2). Block variety and nesting are later slices.
///
/// Marks ride the wire as `YXmlText` delta formatting attributes
/// (`marksToAttributes`). Because Yjs deep-change observers cannot carry
/// object-valued attributes back to us, a remote change triggers a deferred
/// full-replica reconcile rather than replaying the observed delta.
@MainActor
public final class YBinding {
    /// y-prosemirror's default root name. Tiptap defaults to `"default"`; both
    /// peers MUST agree or they silently never converge (see `attach`).
    public static let defaultFragmentName = "prosemirror"

    private let core: EditorCore
    private let doc: YDoc
    private let fragment: YXmlFragment

    private enum Replica {
        static let paragraphElementName = "paragraph"
        static let bindingOrigin = "prosekit-yjs-binding"

        static func textNode(in fragment: YXmlFragment, transaction: YReadTransaction) throws -> YXmlText? {
            guard try transaction.childCount(of: fragment) > 0,
                  case let .element(paragraph) = try transaction.child(at: 0, in: fragment)
            else { return nil }
            return try textNode(in: paragraph, transaction: transaction)
        }

        static func ensureParagraph(in fragment: YXmlFragment, transaction: YWriteTransaction) throws -> YXmlElement {
            if try transaction.childCount(of: fragment) > 0,
               case let .element(paragraph) = try transaction.child(at: 0, in: fragment) {
                return paragraph
            }
            return try transaction.insertElement(named: paragraphElementName, into: fragment, at: 0)
        }

        static func ensureTextNode(in paragraph: YXmlElement, transaction: YWriteTransaction) throws -> YXmlText {
            if let textNode = try textNode(in: paragraph, transaction: transaction) {
                return textNode
            }
            return try transaction.insertText(into: paragraph, at: 0)
        }

        private static func textNode(in paragraph: YXmlElement, transaction: YReadTransaction) throws -> YXmlText? {
            guard try transaction.childCount(of: paragraph) > 0,
                  case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
            else { return nil }
            return textNode
        }
    }

    private var fragmentObservation: Observation?
    /// SwiftYrs has no deep observation, and a text/formatting change inside
    /// `paragraph > text` is a deep change the fragment observer never sees. We
    /// also observe the inner `YXmlText` directly; its branch identity is stable
    /// for the document's lifetime, so one observation suffices.
    private var textObservation: Observation?
    private var syncTask: Task<Void, Never>?

    /// True while we are writing our own change into Y. The fragment/text
    /// observers fire synchronously inside that write, so this guard breaks the loop.
    private var isApplyingLocalWrite = false

    /// Gates the encoder/decoder until the provider's first sync completes.
    private var hasJoined = false

    /// True while a deferred reconcile is already queued, so a burst of Y events
    /// coalesces into one.
    private var isReconcileScheduled = false

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
        fragmentObservation = try? fragment.observe { event in
            guard case .shared = event else { return }
            // The observer fires synchronously inside a MainActor-confined
            // write/apply, so we are already on the MainActor here.
            MainActor.assumeIsolated { [weak self] in
                self?.scheduleReconcile()
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
        fragmentObservation = nil
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
        let replica = currentReplicaMarkedText()
        let document = documentMarkedText(core.document)
        switch (replica.runs.isEmpty, document.runs.isEmpty) {
        case (false, _):
            applyReplica(replica)
        case (true, false):
            encodeToReplica(document)
        case (true, true):
            // Leave Y structure-free so the first peer to type creates the paragraph.
            break
        }
        bindTextObservationIfAvailable()
    }

    // MARK: - Scheduling

    /// A remote update changed the replica. We cannot read Y structure inside the
    /// observer (the apply's write txn still holds the lock), so the bind + decode
    /// are deferred until the transaction releases.
    private func scheduleReconcile() {
        guard hasJoined, !isApplyingLocalWrite, !isReconcileScheduled else { return }
        isReconcileScheduled = true
        Task { @MainActor [weak self] in
            self?.reconcileFromReplica()
        }
    }

    private func reconcileFromReplica() {
        isReconcileScheduled = false
        guard hasJoined, !isApplyingLocalWrite else { return }
        bindTextObservationIfAvailable()
        applyReplica(currentReplicaMarkedText())
    }

    /// Observes the inner text node once it exists. Idempotent.
    private func bindTextObservationIfAvailable() {
        guard textObservation == nil, let textNode = currentEditableTextNode() else { return }
        textObservation = try? textNode.observe { event in
            guard case .shared = event else { return }
            MainActor.assumeIsolated { [weak self] in
                self?.scheduleReconcile()
            }
        }
    }

    // MARK: - Encoder (PM → Y)

    private func handleLocalTransaction(_ applied: AppliedTransaction) {
        // A remote apply already matches the replica; re-encoding it would echo.
        guard hasJoined, applied.origin != .remote else { return }
        encodeToReplica(documentMarkedText(applied.document))
    }

    private func encodeToReplica(_ target: MarkedText) {
        isApplyingLocalWrite = true
        defer { isApplyingLocalWrite = false }
        try? doc.write(origin: Replica.bindingOrigin) { transaction in
            let paragraph = try Replica.ensureParagraph(in: fragment, transaction: transaction)
            let textNode = try Replica.ensureTextNode(in: paragraph, transaction: transaction)

            // 1. Text characters: minimal common-prefix/suffix diff so a concurrent
            //    remote insert into the same run survives.
            let before = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode))
            let diff = TextDiff(from: before.plainText, to: target.plainText)
            if diff.removedLength > 0 {
                try transaction.remove(from: textNode, at: UInt32(diff.prefix), length: UInt32(diff.removedLength))
            }
            if !diff.inserted.isEmpty {
                try transaction.insert(diff.inserted, into: textNode, at: UInt32(diff.prefix))
            }

            // 2. Formatting: bring the per-character Marks to the target via format
            //    ops (a new mark sets its attrs object; a dropped mark sets null).
            let current = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode))
            try reconcileFormatting(textNode, from: current, to: target, transaction: transaction)
        }
        bindTextObservationIfAvailable()
    }

    private func reconcileFormatting(
        _ textNode: YXmlText,
        from current: MarkedText,
        to target: MarkedText,
        transaction: YWriteTransaction
    ) throws {
        let currentMarks = current.marksPerCharacter
        let targetMarks = target.marksPerCharacter
        let count = min(currentMarks.count, targetMarks.count)
        var index = 0
        while index < count {
            let change = formatChange(from: currentMarks[index], to: targetMarks[index])
            guard !change.isEmpty else { index += 1; continue }
            var end = index + 1
            while end < count,
                  NSDictionary(dictionary: formatChange(from: currentMarks[end], to: targetMarks[end]))
                    == NSDictionary(dictionary: change) {
                end += 1
            }
            let data = try JSONSerialization.data(withJSONObject: change)
            try transaction.format(textNode, at: UInt32(index), length: UInt32(end - index), attributesJSON: data)
            index = end
        }
    }

    /// The format attributes that turn `current` Marks into `target` Marks at one
    /// character: each changed key maps to the target mark's attrs object, or
    /// `NSNull` to clear a mark `target` no longer carries.
    private func formatChange(from current: [Mark], to target: [Mark]) -> [String: Any] {
        let currentAttrs = MarkAttributes.attributes(for: current)
        let targetAttrs = MarkAttributes.attributes(for: target)
        var change: [String: Any] = [:]
        for key in Set(currentAttrs.keys).union(targetAttrs.keys) where currentAttrs[key] != targetAttrs[key] {
            if let attrs = targetAttrs[key] {
                change[key] = MarkedText.foundationObject(from: attrs)
            } else {
                change[key] = NSNull()
            }
        }
        return change
    }

    // MARK: - Decoder (Y → PM)

    /// Reconciles the local `Document` to the replica's marked text via a single
    /// `.remote` transaction: a minimal text diff (so the caret survives), then
    /// per-run mark Steps. Used by the Join gate and every deferred reconcile.
    private func applyReplica(_ target: MarkedText) {
        let document = core.document
        let base = textBasePosition
        let current = documentMarkedText(document)

        var steps: [any Step] = []
        var working = document

        let diff = TextDiff(from: current.plainText, to: target.plainText)
        if diff.hasChange {
            let step = ReplaceStep(
                from: base + diff.prefix,
                to: base + diff.prefix + diff.removedLength,
                insertText: diff.inserted
            )
            steps.append(step)
            working = (try? step.apply(to: working).document) ?? working
        }

        steps.append(contentsOf: markSteps(in: working, base: base, target: target))
        applyRemoteSteps(steps)
    }

    /// Mark Steps that turn the document's current Marks into the target's.
    ///
    /// Iterates the document's **text nodes** (not a per-character span): adjacent
    /// runs that happen to share a Mark set are still separate nodes, and the Mark
    /// algebra requires each Step's range to stay inside one node. Within a node
    /// the current Marks are uniform, so the range is split only where the target
    /// Marks change. The working document is advanced as Steps apply, so a node
    /// that splits out keeps later ranges resolvable.
    private func markSteps(in document: Document, base: Position, target: MarkedText) -> [any Step] {
        let targetMarks = target.marksPerCharacter
        var steps: [any Step] = []
        var working = document
        var offset = 0

        for run in documentMarkedText(document).runs {
            let runStart = offset
            let runEnd = offset + run.text.count
            offset = runEnd
            let currentSet = Set(run.marks)

            var index = runStart
            while index < runEnd, index < targetMarks.count {
                let targetSet = Set(targetMarks[index])
                if currentSet == targetSet { index += 1; continue }

                var end = index + 1
                while end < runEnd, end < targetMarks.count, Set(targetMarks[end]) == targetSet {
                    end += 1
                }

                let range = (base + index)..<(base + end)
                for mark in currentSet.subtracting(targetSet) {
                    let step = RemoveMarkStep(from: range.lowerBound, to: range.upperBound, mark: mark)
                    if let next = try? step.apply(to: working).document {
                        steps.append(step)
                        working = next
                    }
                }
                for mark in targetSet.subtracting(currentSet) {
                    let step = AddMarkStep(from: range.lowerBound, to: range.upperBound, mark: mark)
                    if let next = try? step.apply(to: working).document {
                        steps.append(step)
                        working = next
                    }
                }
                index = end
            }
        }
        return steps
    }

    private func applyRemoteSteps(_ steps: [any Step]) {
        guard !steps.isEmpty else { return }
        let mapping = Mapping(steps)
        let mappedSelection = core.selection.mapped(through: mapping)
        core.applyRemote(Transaction(steps: steps, selection: mappedSelection, origin: .remote))
    }

    // MARK: - Reads

    /// The Position of the first text character in the single paragraph. For a
    /// flat single-paragraph document this is the paragraph's open token + 1.
    private var textBasePosition: Position {
        core.document.endTextPosition - core.document.totalTextCount
    }

    private func documentMarkedText(_ document: Document) -> MarkedText {
        guard let block = document.root.content.first else { return MarkedText(runs: []) }
        return MarkedText(textblock: block)
    }

    private func currentReplicaMarkedText() -> MarkedText {
        let data = (try? doc.read { transaction -> Data in
            guard let node = try Replica.textNode(in: fragment, transaction: transaction) else { return Data() }
            return try transaction.deltaJSON(from: node)
        }) ?? Data()
        return MarkedText(deltaJSON: data)
    }

    private func currentEditableTextNode() -> YXmlText? {
        (try? doc.read { transaction in
            try Replica.textNode(in: fragment, transaction: transaction)
        }) ?? nil
    }
}

/// A minimal common prefix/suffix text diff. Indices are in `Character`s, which
/// equals UTF-16 code units for the BMP (sufficient for the marks slice; non-BMP
/// handling is a later-slice concern).
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
