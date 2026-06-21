import Foundation
import ProseEditor
import ProseModel
import SwiftYrs

/// Binds an `EditorCore` to a Yjs `YXmlFragment`, converging an arbitrarily
/// nested document (`doc > block+`, blocks nesting through containers like lists)
/// with a y-prosemirror peer. Inline Marks, flat block types/Attrs, and nesting
/// all converge.
///
/// Each ProseMirror block is a `YXmlElement` whose `nodeName` is the Schema type
/// and whose element attributes are the block's Attrs. A textblock's single
/// `YXmlText` child carries the inline content (text + mark formatting); a
/// container's children are nested block `YXmlElement`s. A remote change triggers
/// a deferred full-replica reconcile, because Yjs deep-change observers cannot
/// carry object-valued attributes back to us.
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

    /// The node types ProseKit understands. A type outside this set is an Opaque
    /// Node (ADR 0006): its `YXmlElement` subtree is preserved verbatim, never
    /// reinterpreted or restructured (#70, convergence-critical).
    private let knownNodeTypes: Set<String>

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
        self.knownNodeTypes = core.schema.nodes
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

    /// Observes every element **and text node** in the fragment subtree (and
    /// re-binds on structure changes), so a deep change anywhere — element
    /// attributes, or text/formatting inside a `YXmlText` the container observers
    /// never see — schedules a reconcile.
    private func observeBlocks() {
        let nodes = (try? doc.read { transaction -> [YSharedType] in
            var observed: [YSharedType] = []
            try collectObservable(in: fragment, transaction: transaction, into: &observed)
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

    private func collectObservable(in container: YXmlContainer, transaction: YReadTransaction, into observed: inout [YSharedType]) throws {
        let count = try transaction.childCount(of: container)
        for index in 0..<count {
            switch try transaction.child(at: index, in: container) {
            case let .element(element):
                observed.append(element)
                try collectObservable(in: element, transaction: transaction, into: &observed)
            case let .text(textNode):
                observed.append(textNode)
            case .fragment:
                break
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
            try reconcileChildren(of: fragment, to: blocks, transaction: transaction)
        }
        observeBlocks()
    }

    /// Reconciles a container's child block elements to `nodes` (the fragment, or
    /// a nested container such as a list). A matched `nodeName` mutates in place;
    /// a changed type is delete+insert; surplus children are trimmed. The
    /// recursion (via `reconcileBlock`) only touches changed positions, so an
    /// untouched sibling keeps its `YXmlElement` identity.
    private func reconcileChildren(of container: YXmlContainer, to nodes: [Node], transaction: YWriteTransaction) throws {
        var index = 0
        while index < nodes.count {
            let target = nodes[index]
            let count = try transaction.childCount(of: container)
            if index < count,
               case let .element(element) = try transaction.child(at: UInt32(index), in: container),
               try transaction.tag(of: element) == target.type {
                try reconcileBlock(element, to: target, transaction: transaction)
            } else {
                if index < count {
                    try transaction.remove(from: container, at: UInt32(index), length: 1)
                }
                try insertBlock(target, into: container, at: UInt32(index), transaction: transaction)
            }
            index += 1
        }
        let count = try transaction.childCount(of: container)
        if count > UInt32(nodes.count) {
            try transaction.remove(from: container, at: UInt32(nodes.count), length: count - UInt32(nodes.count))
        }
    }

    private func insertBlock(_ block: Node, into container: YXmlContainer, at index: UInt32, transaction: YWriteTransaction) throws {
        let element = try transaction.insertElement(named: block.type, into: container, at: index)
        for (key, value) in block.attrs where key != Self.reservedAttributeKey && value != .null {
            try transaction.setAttribute(yValue(value), forKey: key, in: element)
        }
        try buildContent(of: element, from: block, transaction: transaction)
    }

    /// Builds a freshly-inserted element's content from a Node. An Opaque Node is
    /// reconstructed by its content shape alone (text run, child elements, or — an
    /// atom — nothing), so a childless unknown node never gains a spurious text
    /// child; a known textblock seeds its (possibly empty) `YXmlText`.
    private func buildContent(of element: YXmlElement, from block: Node, transaction: YWriteTransaction) throws {
        if isOpaque(block) {
            if block.content.contains(where: \.isText) {
                let textNode = try transaction.insertText(into: element, at: 0)
                try transaction.applyDeltaJSON(MarkedText(textblock: block).deltaJSON(), to: textNode)
            } else {
                try reconcileChildren(of: element, to: block.content, transaction: transaction)
            }
        } else if block.isTextblock {
            let textNode = try transaction.insertText(into: element, at: 0)
            try reconcileText(textNode, to: MarkedText(textblock: block), transaction: transaction)
        } else {
            try reconcileChildren(of: element, to: block.content, transaction: transaction)
        }
    }

    /// Mutates a matched block element **in place** (attrs patched, content
    /// reconciled) so a concurrent remote edit into it survives.
    private func reconcileBlock(_ element: YXmlElement, to target: Node, transaction: YWriteTransaction) throws {
        // An Opaque Node's subtree is never touched: ProseKit cannot author or
        // edit it, so its decoded Node already equals the replica. Re-encoding it
        // could restructure content SwiftYrs/PM model differently (e.g. add a text
        // child to an atom) — exactly the data loss #70 forbids.
        guard !isOpaque(target) else { return }
        try reconcileAttributes(element, to: target.attrs, transaction: transaction)
        try reconcileContent(of: element, to: target, transaction: transaction)
    }

    /// A textblock's content is its single `YXmlText`; a container's is its child
    /// block elements (recursed).
    private func reconcileContent(of element: YXmlElement, to target: Node, transaction: YWriteTransaction) throws {
        if target.isTextblock {
            let textNode = try ensureTextChild(of: element, transaction: transaction)
            try reconcileText(textNode, to: MarkedText(textblock: target), transaction: transaction)
        } else {
            try reconcileChildren(of: element, to: target.content, transaction: transaction)
        }
    }

    private func isOpaque(_ node: Node) -> Bool {
        !node.isText && !knownNodeTypes.contains(node.type)
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
        // Converting a former container element to a textblock: clear its child
        // elements before seeding the single text node.
        let count = try transaction.childCount(of: element)
        if count > 0 {
            try transaction.remove(from: element, at: 0, length: count)
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

    /// Reconciles the local `Document` to the replica. The diff descends into a
    /// lone changed container so the re-diff (and any `ReplaceBlocksStep`) is
    /// bounded to the deepest changed node; a textblock's inline edit keeps the
    /// fine-grained, caret-preserving text+mark path. Identical leading/trailing
    /// siblings are skipped at every level (so untouched siblings are untouched).
    private func applyReplica(_ target: [Node]) {
        let document = core.document
        guard document.root.content != target else { return }
        var steps: [any Step] = []
        diffChildren(parentPath: [], current: document.root.content, target: target, in: document, steps: &steps)
        applyRemoteSteps(steps)
    }

    private func diffChildren(parentPath: [Int], current: [Node], target: [Node], in document: Document, steps: inout [any Step]) {
        if current == target { return }
        let prefix = commonPrefix(current, target)
        let suffix = commonSuffix(current, target, skipping: prefix)
        let range = prefix..<(current.count - suffix)
        let targetSlice = Array(target[prefix..<(target.count - suffix)])

        if range.count == 1, targetSlice.count == 1,
           current[range.lowerBound].type == targetSlice[0].type,
           current[range.lowerBound].attrs == targetSlice[0].attrs {
            let childPath = parentPath + [range.lowerBound]
            let currentChild = current[range.lowerBound]
            let targetChild = targetSlice[0]
            if targetChild.isTextblock, currentChild.isTextblock {
                inlineSteps(path: childPath, target: MarkedText(textblock: targetChild), in: document, steps: &steps)
            } else {
                diffChildren(parentPath: childPath, current: currentChild.content, target: targetChild.content, in: document, steps: &steps)
            }
            return
        }

        guard let from = childPosition(parentPath: parentPath, index: range.lowerBound, in: document) else { return }
        let removedSize = current[range].reduce(0) { $0 + $1.nodeSize }
        steps.append(ReplaceBlocksStep(
            parentPath: parentPath,
            blockRange: range,
            blocks: targetSlice,
            from: from,
            removedSize: removedSize
        ))
    }

    /// The textblock text+mark reconcile (the common keystroke path): a minimal
    /// text diff carrying the caret, then per-text-node mark Steps, at the
    /// textblock addressed by `path`.
    private func inlineSteps(path: [Int], target: MarkedText, in document: Document, steps: inout [any Step]) {
        guard let nodePosition = document.position(ofNodeAtPath: path) else { return }
        let base = nodePosition + 1
        let current = MarkedText(textblock: document.node(atPath: path))

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
        steps.append(contentsOf: markSteps(at: path, base: base, in: working, target: target))
    }

    /// Mark Steps that turn the textblock at `path`'s current Marks into the
    /// target's, each held inside one text node (adjacent same-mark nodes are
    /// separate), as the Mark algebra requires; the working document advances as
    /// Steps apply.
    private func markSteps(at path: [Int], base: Position, in document: Document, target: MarkedText) -> [any Step] {
        let targetMarks = target.marksPerCharacter
        var steps: [any Step] = []
        var working = document
        var offset = 0

        for run in MarkedText(textblock: document.node(atPath: path)).runs {
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

    /// The block tree the replica currently encodes, decoded recursively from the
    /// fragment: each `YXmlElement` → a Node (`nodeName` → type, attributes →
    /// Attrs); a `YXmlText` first child → inline runs, otherwise child elements
    /// recurse as nested blocks.
    private func replicaBlocks() -> [Node] {
        (try? doc.read { transaction in
            try decodeChildren(of: fragment, transaction: transaction)
        }) ?? []
    }

    private func decodeChildren(of container: YXmlContainer, transaction: YReadTransaction) throws -> [Node] {
        let count = try transaction.childCount(of: container)
        return try (0..<count).compactMap { index -> Node? in
            guard case let .element(element) = try transaction.child(at: index, in: container) else { return nil }
            return try decodeElement(element, transaction: transaction)
        }
    }

    private func decodeElement(_ element: YXmlElement, transaction: YReadTransaction) throws -> Node {
        let type = try transaction.tag(of: element)
        let attrsObject = (try? JSONSerialization.jsonObject(with: transaction.attributesJSON(from: element))) as? [String: Any] ?? [:]
        let attrs = MarkedText.attributes(fromJSON: attrsObject)
        let childCount = try transaction.childCount(of: element)
        let content: [Node]
        if childCount > 0, case let .text(textNode) = try transaction.child(at: 0, in: element) {
            content = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode)).runs.map {
                Node.text($0.text, marks: $0.marks)
            }
        } else {
            content = try decodeChildren(of: element, transaction: transaction)
        }
        return Node(type: type, attrs: attrs, content: content)
    }

    /// The Position where child `index` of the container at `parentPath` begins;
    /// for an append (`index == childCount`) the container's closing token.
    private func childPosition(parentPath: [Int], index: Int, in document: Document) -> Position? {
        let parent = parentPath.isEmpty ? document.root : document.node(atPath: parentPath)
        if index < parent.content.count {
            return document.position(ofNodeAtPath: parentPath + [index])
        }
        if parentPath.isEmpty { return document.endPosition }
        guard let parentPosition = document.position(ofNodeAtPath: parentPath) else { return nil }
        return parentPosition + parent.nodeSize - 1
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
