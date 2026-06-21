import Foundation
import ProseEditor
import ProseModel
import SwiftYrs

/// Binds an `EditorCore` to a Yjs `YXmlFragment`, converging a **flat** document
/// (`doc > block+`, each block a textblock of inline content) with a
/// y-prosemirror peer. Slice 2 added inline Marks; slice 3 (this) adds the full
/// set of flat block types and their Attrs. Nesting is a later slice.
///
/// Each ProseMirror block is a `YXmlElement` whose `nodeName` is the Schema type
/// and whose element attributes are the block's Attrs; its single `YXmlText`
/// child carries the inline content (text + mark formatting). A remote change
/// triggers a deferred full-replica reconcile, because Yjs deep-change observers
/// cannot carry object-valued attributes back to us.
@MainActor
public final class YBinding {
    /// y-prosemirror's default root name. Tiptap defaults to `"default"`; both
    /// peers MUST agree or they silently never converge (see `attach`).
    public static let defaultFragmentName = "prosemirror"

    /// Reserved by y-prosemirror for snapshot diff rendering — never written, skipped on read.
    private static let reservedAttributeKey = "ychange"
    private static let bindingOrigin = "prosekit-yjs-binding"

    private let core: EditorCore
    private let doc: YDoc
    private let fragment: YXmlFragment

    private var fragmentObservation: Observation?
    /// A change inside a block (text, formatting, attrs) is deep — the fragment
    /// observer never sees it — so each block's `YXmlElement` is observed too. The
    /// observed set is reconciled to the current children on every reconcile.
    private var blockObservations: [Observation] = []
    private var syncTask: Task<Void, Never>?

    /// True while we are writing our own change into Y. The observers fire
    /// synchronously inside that write, so this guard breaks the loop.
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
        blockObservations = []
        core.didApplyTransaction = nil
        hasJoined = false
    }

    /// The Join reconcile (idempotent): an empty replica is seeded from the local
    /// `Document`; a non-empty replica replaces the local `Document` (`.remote`,
    /// no history). Exposed for tests that drive the gate without a provider.
    func join() {
        guard !hasJoined else { return }
        hasJoined = true
        let replica = replicaBlocks()
        let document = core.document.root.content
        switch (replica.isEmpty, core.document.plainText.isEmpty) {
        case (false, _):
            applyReplica(replica)
        case (true, false):
            encodeToReplica(document)
        case (true, true):
            break // an empty document must not seed a competing empty block
        }
        observeBlocks()
    }

    // MARK: - Scheduling

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
        observeBlocks()
        applyReplica(replicaBlocks())
    }

    /// Observes every current block element **and its inner text node** (and
    /// re-binds on structure changes), so a deep change — element attributes, or
    /// text/formatting inside the `YXmlText` grandchild that the element observer
    /// never sees — schedules a reconcile.
    private func observeBlocks() {
        let nodes = (try? doc.read { transaction -> [YSharedType] in
            let count = try transaction.childCount(of: fragment)
            var observed: [YSharedType] = []
            for index in 0..<count {
                guard case let .element(element) = try transaction.child(at: index, in: fragment) else { continue }
                observed.append(element)
                if try transaction.childCount(of: element) > 0,
                   case let .text(textNode) = try transaction.child(at: 0, in: element) {
                    observed.append(textNode)
                }
            }
            return observed
        }) ?? []
        blockObservations = nodes.compactMap { node in
            try? node.observe { event in
                guard case .shared = event else { return }
                MainActor.assumeIsolated { [weak self] in
                    self?.scheduleReconcile()
                }
            }
        }
    }

    // MARK: - Encoder (PM → Y)

    private func handleLocalTransaction(_ applied: AppliedTransaction) {
        guard hasJoined, applied.origin != .remote else { return }
        encodeToReplica(applied.document.root.content)
    }

    private func encodeToReplica(_ blocks: [Node]) {
        isApplyingLocalWrite = true
        defer { isApplyingLocalWrite = false }
        try? doc.write(origin: Self.bindingOrigin) { transaction in
            var index = 0
            while index < blocks.count {
                let target = blocks[index]
                let count = try transaction.childCount(of: fragment)
                if index < count,
                   case let .element(element) = try transaction.child(at: UInt32(index), in: fragment),
                   try transaction.tag(of: element) == target.type {
                    try reconcileBlock(element, to: target, transaction: transaction)
                } else {
                    if index < count {
                        try transaction.remove(from: fragment, at: UInt32(index), length: 1)
                    }
                    try insertBlock(target, at: UInt32(index), transaction: transaction)
                }
                index += 1
            }
            let count = try transaction.childCount(of: fragment)
            if count > UInt32(blocks.count) {
                try transaction.remove(from: fragment, at: UInt32(blocks.count), length: count - UInt32(blocks.count))
            }
        }
        observeBlocks()
    }

    private func insertBlock(_ block: Node, at index: UInt32, transaction: YWriteTransaction) throws {
        let element = try transaction.insertElement(named: block.type, into: fragment, at: index)
        for (key, value) in block.attrs where key != Self.reservedAttributeKey && value != .null {
            try transaction.setAttribute(yValue(value), forKey: key, in: element)
        }
        let textNode = try transaction.insertText(into: element, at: 0)
        try reconcileText(textNode, to: MarkedText(textblock: block), transaction: transaction)
    }

    /// Mutates a matched block element **in place** (attrs patched, text child
    /// reconciled) so a concurrent remote edit into it survives.
    private func reconcileBlock(_ element: YXmlElement, to target: Node, transaction: YWriteTransaction) throws {
        try reconcileAttributes(element, to: target.attrs, transaction: transaction)
        let textNode = try ensureTextChild(of: element, transaction: transaction)
        try reconcileText(textNode, to: MarkedText(textblock: target), transaction: transaction)
    }

    private func reconcileAttributes(_ element: YXmlElement, to target: [String: JSONValue], transaction: YWriteTransaction) throws {
        let object = (try? JSONSerialization.jsonObject(with: transaction.attributesJSON(from: element))) as? [String: Any] ?? [:]
        let current = MarkedText.attributes(fromJSON: object)
        for (key, value) in target where key != Self.reservedAttributeKey && value != .null {
            if current[key] != value {
                try transaction.setAttribute(yValue(value), forKey: key, in: element)
            }
        }
        for key in current.keys where key != Self.reservedAttributeKey {
            let targetValue = target[key]
            if targetValue == nil || targetValue == .null {
                try transaction.removeAttribute(key, from: element)
            }
        }
    }

    private func ensureTextChild(of element: YXmlElement, transaction: YWriteTransaction) throws -> YXmlText {
        if try transaction.childCount(of: element) > 0,
           case let .text(textNode) = try transaction.child(at: 0, in: element) {
            return textNode
        }
        return try transaction.insertText(into: element, at: 0)
    }

    /// Brings a `YXmlText` to `target`: a minimal text diff (so a concurrent
    /// remote insert survives) then a per-character format reconcile (a new mark
    /// sets its attrs object; a dropped mark sets null).
    private func reconcileText(_ textNode: YXmlText, to target: MarkedText, transaction: YWriteTransaction) throws {
        let before = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode))
        let diff = TextDiff(from: before.plainText, to: target.plainText)
        if diff.removedLength > 0 {
            try transaction.remove(from: textNode, at: UInt32(diff.prefix), length: UInt32(diff.removedLength))
        }
        if !diff.inserted.isEmpty {
            try transaction.insert(diff.inserted, into: textNode, at: UInt32(diff.prefix))
        }
        let current = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode))
        try reconcileFormatting(textNode, from: current, to: target, transaction: transaction)
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

    /// Reconciles the local `Document`'s blocks to the replica's. Identical
    /// leading/trailing blocks are skipped; a lone block whose only difference is
    /// inline content takes the fine-grained text+mark path (so the caret
    /// survives); any structural change (type, attrs, count) is a `ReplaceBlocksStep`.
    private func applyReplica(_ target: [Node]) {
        let document = core.document
        let current = document.root.content
        guard current != target else { return }

        let prefix = commonPrefix(current, target)
        let suffix = commonSuffix(current, target, skipping: prefix)
        let currentRange = prefix..<(current.count - suffix)
        let targetSlice = Array(target[prefix..<(target.count - suffix)])

        if currentRange.count == 1, targetSlice.count == 1,
           current[currentRange.lowerBound].type == targetSlice[0].type,
           current[currentRange.lowerBound].attrs == targetSlice[0].attrs {
            applyInlineReplica(blockIndex: currentRange.lowerBound, target: MarkedText(textblock: targetSlice[0]))
            return
        }

        guard let from = blockPosition(at: currentRange.lowerBound, in: document) else { return }
        let removedSize = current[currentRange].reduce(0) { $0 + $1.nodeSize }
        let step = ReplaceBlocksStep(
            blockRange: currentRange,
            blocks: targetSlice,
            from: from,
            removedSize: removedSize
        )
        applyRemoteSteps([step])
    }

    /// The single-block text+mark reconcile (the common keystroke path): minimal
    /// text diff carrying the caret, then per-text-node mark Steps.
    private func applyInlineReplica(blockIndex: Int, target: MarkedText) {
        let document = core.document
        guard let base = document.position(ofTextInBlockAt: blockIndex) else { return }
        let current = MarkedText(textblock: document.root.content[blockIndex])

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
        steps.append(contentsOf: markSteps(in: working, blockIndex: blockIndex, target: target))
        applyRemoteSteps(steps)
    }

    /// Mark Steps that turn block `blockIndex`'s current Marks into the target's,
    /// each held inside one text node (adjacent same-mark nodes are separate), as
    /// the Mark algebra requires; the working document advances as Steps apply.
    private func markSteps(in document: Document, blockIndex: Int, target: MarkedText) -> [any Step] {
        guard let base = document.position(ofTextInBlockAt: blockIndex),
              document.root.content.indices.contains(blockIndex) else { return [] }
        let targetMarks = target.marksPerCharacter
        var steps: [any Step] = []
        var working = document
        var offset = 0

        for run in MarkedText(textblock: document.root.content[blockIndex]).runs {
            let runEnd = offset + run.text.count
            let currentSet = Set(run.marks)
            var index = offset
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
                    if let next = try? step.apply(to: working).document { steps.append(step); working = next }
                }
                for mark in targetSet.subtracting(currentSet) {
                    let step = AddMarkStep(from: range.lowerBound, to: range.upperBound, mark: mark)
                    if let next = try? step.apply(to: working).document { steps.append(step); working = next }
                }
                index = end
            }
            offset = runEnd
        }
        return steps
    }

    private func applyRemoteSteps(_ steps: [any Step]) {
        guard !steps.isEmpty else { return }
        let mapping = Mapping(steps)
        let mappedSelection = core.selection.mapped(through: mapping)
        core.applyRemote(Transaction(steps: steps, selection: mappedSelection, origin: .remote))
    }

    // MARK: - Replica reads

    /// The block nodes the replica currently encodes: one per `YXmlElement` child
    /// of the fragment (`nodeName` → type, attributes → Attrs, text child → runs).
    private func replicaBlocks() -> [Node] {
        (try? doc.read { transaction -> [Node] in
            let count = try transaction.childCount(of: fragment)
            return try (0..<count).compactMap { index -> Node? in
                guard case let .element(element) = try transaction.child(at: index, in: fragment) else { return nil }
                let type = try transaction.tag(of: element)
                let attrsObject = (try? JSONSerialization.jsonObject(with: transaction.attributesJSON(from: element))) as? [String: Any] ?? [:]
                let attrs = MarkedText.attributes(fromJSON: attrsObject)
                let runs = try blockRuns(of: element, transaction: transaction)
                return Node(
                    type: type,
                    attrs: attrs,
                    content: runs.map { Node.text($0.text, marks: $0.marks) }
                )
            }
        }) ?? []
    }

    private func blockRuns(of element: YXmlElement, transaction: YReadTransaction) throws -> [MarkedRun] {
        guard try transaction.childCount(of: element) > 0,
              case let .text(textNode) = try transaction.child(at: 0, in: element)
        else { return [] }
        return MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode)).runs
    }

    private func blockPosition(at index: Int, in document: Document) -> Position? {
        if index < document.root.content.count {
            return document.position(ofBlockAt: index)
        }
        return document.endPosition
    }

    private func yValue(_ value: JSONValue) -> YValue {
        switch value {
        case let .string(string): return .string(string)
        // y-prosemirror/lib0 encodes every number as a double; match it so an
        // integer attr (e.g. heading.level) converges with the JS peer and is not
        // an i64 the browser decodes as an unserialisable BigInt.
        case let .int(int): return .double(Double(int))
        case let .double(double): return .double(double)
        case let .bool(bool): return .bool(bool)
        case .null: return .undefined
        }
    }
}

private func commonPrefix(_ lhs: [Node], _ rhs: [Node]) -> Int {
    var index = 0
    while index < lhs.count, index < rhs.count, lhs[index] == rhs[index] { index += 1 }
    return index
}

private func commonSuffix(_ lhs: [Node], _ rhs: [Node], skipping prefix: Int) -> Int {
    var count = 0
    while count < lhs.count - prefix,
          count < rhs.count - prefix,
          lhs[lhs.count - 1 - count] == rhs[rhs.count - 1 - count] {
        count += 1
    }
    return count
}

/// A minimal common prefix/suffix text diff. Indices are in `Character`s, which
/// equals UTF-16 code units for the BMP (sufficient for these slices; non-BMP
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
