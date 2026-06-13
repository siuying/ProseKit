public struct Document: Codable, Hashable, Sendable {
    public private(set) var root: Node

    /// The leaf-block tiling (ADR 0007): the document's **leaf blocks**
    /// (textblocks — the units CoreText typesets) enumerated in document order,
    /// at any nesting depth. Precomputed once per Document; Documents are
    /// immutable, so the index cannot go stale, and the paths UIKit hammers
    /// between keystrokes (text(in:), offset math, blockInfo) stay a binary
    /// search instead of re-walking the tree per call.
    ///
    /// The arrays are parallel, one entry per leaf in order. The tree is the
    /// single authority: a leaf's containers are recovered by walking
    /// `root` + its `leafPath`, never duplicated here (parity with ProseMirror,
    /// which has no leaf index at all).
    struct BlockIndex: Hashable, Sendable {
        /// blockStarts[i] is the Position of leaf i's opening token.
        var blockStarts: [Position]
        /// blockTextCounts[i] is leaf i's plainText character count.
        var blockTextCounts: [Int]
        /// blockCharStarts[i] is the sum of plainText counts before leaf i.
        var blockCharStarts: [Int]
        /// leafPaths[i] is the child-index path from the root to leaf i.
        var leafPaths: [[Int]]
        /// Position just past the last top-level child (root.nodeSize - 1).
        var endPosition: Position
        var endTextPosition: Position
        /// True when every leaf is a direct child of the root (depth 1) — the
        /// fast path for incremental index derivation (`derivedIndex`).
        var isFlat: Bool
    }

    var index: BlockIndex

    public init(_ root: Node) {
        self.root = root
        self.index = Self.makeIndex(of: root)
    }

    private init(root: Node, index: BlockIndex) {
        self.root = root
        self.index = index
    }

    public init(from decoder: Decoder) throws {
        root = try Node(from: decoder)
        index = Self.makeIndex(of: root)
    }

    public func encode(to encoder: Encoder) throws {
        try root.encode(to: encoder)
    }

    public var endPosition: Int {
        index.endPosition
    }

    public var endTextPosition: Position {
        index.endTextPosition
    }

    /// Depth-first enumeration of the root's leaf blocks. Each container
    /// contributes one Position for its opening token, then its children, then
    /// one for its closing token — so leaf Positions account for every ancestor
    /// boundary. For a flat document this produces exactly the top-level tiling.
    private static func makeIndex(of root: Node) -> BlockIndex {
        var starts: [Position] = []
        var textCounts: [Int] = []
        var charStarts: [Int] = []
        var leafPaths: [[Int]] = []
        var position: Position = 1
        var characters = 0

        func visit(_ node: Node, path: [Int]) {
            if node.isTextblock {
                starts.append(position)
                charStarts.append(characters)
                let count = node.plainText.count
                textCounts.append(count)
                leafPaths.append(path)
                characters += count
                position += node.nodeSize
            } else {
                position += 1 // container opening token
                for (childIndex, child) in node.content.enumerated() {
                    visit(child, path: path + [childIndex])
                }
                position += 1 // container closing token
            }
        }
        for (childIndex, child) in root.content.enumerated() {
            visit(child, path: [childIndex])
        }

        let endTextPosition: Position
        if let lastStart = starts.last, let lastCount = textCounts.last {
            endTextPosition = lastStart + 1 + lastCount
        } else {
            endTextPosition = position
        }
        return BlockIndex(
            blockStarts: starts,
            blockTextCounts: textCounts,
            blockCharStarts: charStarts,
            leafPaths: leafPaths,
            endPosition: position,
            endTextPosition: endTextPosition,
            isFlat: leafPaths.allSatisfy { $0.count == 1 }
        )
    }

    /// The number of leaf blocks (textblocks), at any depth.
    public var blockCount: Int {
        index.blockStarts.count
    }

    /// True when every leaf block is a direct child of the root (depth 1) — a
    /// flat document. The keystroke fast paths (index derivation, layout) key
    /// on this; nested documents take correct-but-unoptimized paths until the
    /// later block-nesting slices.
    public var isFlat: Bool {
        index.isFlat
    }

    /// The leaf block at leaf-order index `i`, fetched by walking its path. The
    /// tree is the authority; the index stores only the path.
    func leafNode(_ i: Int) -> Node {
        var node = root
        for childIndex in index.leafPaths[i] {
            node = node.content[childIndex]
        }
        return node
    }

    /// Document with blocks[range] replaced by `newBlocks`. The index is
    /// derived, not rebuilt: only the new blocks are measured, and the tail
    /// entries shift by constant deltas. Rebuilding (`makeIndex`) re-counts
    /// every block's text, which made each keystroke O(document).
    ///
    /// The block-replace primitive: the one write seam every Step builds on.
    /// Steps choose the new blocks; the index derivation behind this stays
    /// private (the O(log blocks) keystroke invariant).
    func replacingBlocks(in range: Range<Int>, with newBlocks: [Node]) -> Document {
        var blocks = root.content
        blocks.replaceSubrange(range, with: newBlocks)
        let newRoot = root.withContent(blocks)
        // Incremental derivation only holds when the document stays flat — every
        // leaf a direct child of the root. A nested document (or one becoming
        // nested) rebuilds the leaf tiling; making that incremental too is
        // slice 02 (.scratch/block-nesting/issues/02). Flat editing — the
        // keystroke hot path — keeps the O(blocks) derived update.
        let staysFlat = index.isFlat && newBlocks.allSatisfy(\.isTextblock)
        return Document(
            root: newRoot,
            index: staysFlat
                ? derivedIndex(replacingBlocksIn: range, with: newBlocks)
                : Self.makeIndex(of: newRoot)
        )
    }

    /// Path-addressed block replace: replaces `childRange` of the container at
    /// `parentPath` (root-to-container child indices; empty = the root itself)
    /// with `newBlocks`. The structural Steps build on this to edit within a
    /// container at any depth. Top-level edits (`parentPath` empty) keep the
    /// flat fast path; deeper edits rebuild the leaf tiling (incremental nested
    /// derivation is a later slice).
    func replacingBlocks(at parentPath: [Int], childRange: Range<Int>, with newBlocks: [Node]) -> Document {
        guard !parentPath.isEmpty else {
            return replacingBlocks(in: childRange, with: newBlocks)
        }
        let newRoot = root.replacingChildren(atPath: parentPath, range: childRange, with: newBlocks)
        return Document(root: newRoot, index: Self.makeIndex(of: newRoot))
    }

    /// The node at `path` (root-to-node child indices); the root when empty.
    public func node(atPath path: [Int]) -> Node {
        var node = root
        for childIndex in path {
            node = node.content[childIndex]
        }
        return node
    }

    /// The Position of the node at `path` (root-to-node child indices); the
    /// root is Position 0.
    public func position(ofNodeAtPath path: [Int]) -> Position? {
        guard !path.isEmpty else { return 0 }
        var node = root
        var position: Position = 1
        for (depth, childIndex) in path.enumerated() {
            guard node.content.indices.contains(childIndex) else { return nil }
            for siblingIndex in 0..<childIndex {
                position += node.content[siblingIndex].nodeSize
            }
            let child = node.content[childIndex]
            if depth == path.count - 1 {
                return position
            }
            position += 1
            node = child
        }
        return nil
    }

    private func derivedIndex(replacingBlocksIn range: Range<Int>, with newBlocks: [Node]) -> BlockIndex {
        var starts = index.blockStarts
        var textCounts = index.blockTextCounts
        var charStarts = index.blockCharStarts
        let totalCharacters = (charStarts.last ?? 0) + (textCounts.last ?? 0)

        var position = range.lowerBound < starts.count ? starts[range.lowerBound] : index.endPosition
        var characters = range.lowerBound < charStarts.count ? charStarts[range.lowerBound] : totalCharacters
        let oldTailPosition = range.upperBound < starts.count ? starts[range.upperBound] : index.endPosition
        let oldTailCharacters = range.upperBound < charStarts.count ? charStarts[range.upperBound] : totalCharacters

        var newStarts: [Position] = []
        var newTextCounts: [Int] = []
        var newCharStarts: [Int] = []
        newStarts.reserveCapacity(newBlocks.count)
        newTextCounts.reserveCapacity(newBlocks.count)
        newCharStarts.reserveCapacity(newBlocks.count)
        for block in newBlocks {
            newStarts.append(position)
            newCharStarts.append(characters)
            let count = block.plainText.count
            newTextCounts.append(count)
            characters += count
            position += block.nodeSize
        }

        let positionDelta = position - oldTailPosition
        let characterDelta = characters - oldTailCharacters
        starts.replaceSubrange(range, with: newStarts)
        textCounts.replaceSubrange(range, with: newTextCounts)
        charStarts.replaceSubrange(range, with: newCharStarts)
        let tailStart = range.lowerBound + newBlocks.count
        if positionDelta != 0 {
            for tailIndex in tailStart..<starts.count {
                starts[tailIndex] += positionDelta
            }
        }
        if characterDelta != 0 {
            for tailIndex in tailStart..<charStarts.count {
                charStarts[tailIndex] += characterDelta
            }
        }
        // Flat document: leaf i is the root's child i, so the path is simply
        // [i]; reindex from the edit point on. (Only reached on the flat fast
        // path — see replacingBlocks.)
        let leafPaths = (0..<starts.count).map { [$0] }

        let endPosition = index.endPosition + positionDelta
        let endTextPosition: Position
        if let lastStart = starts.last, let lastCount = textCounts.last {
            endTextPosition = lastStart + 1 + lastCount
        } else {
            endTextPosition = endPosition
        }
        return BlockIndex(
            blockStarts: starts,
            blockTextCounts: textCounts,
            blockCharStarts: charStarts,
            leafPaths: leafPaths,
            endPosition: endPosition,
            endTextPosition: endTextPosition,
            isFlat: true
        )
    }

    public func position(ofBlockAt blockIndex: Int) -> Position? {
        guard index.blockStarts.indices.contains(blockIndex) else { return nil }
        return index.blockStarts[blockIndex]
    }

    public func position(ofTextInBlockAt blockIndex: Int) -> Position? {
        position(ofBlockAt: blockIndex).map { $0 + 1 }
    }

    /// plainText character count of the block, without materializing it.
    public func textCount(ofBlockAt blockIndex: Int) -> Int? {
        guard index.blockTextCounts.indices.contains(blockIndex) else { return nil }
        return index.blockTextCounts[blockIndex]
    }

    /// Sum of plainText character counts of all blocks before this one.
    public func textCharacters(beforeBlockAt blockIndex: Int) -> Int? {
        guard index.blockCharStarts.indices.contains(blockIndex) else { return nil }
        return index.blockCharStarts[blockIndex]
    }

    /// plainText character count of the whole document (no block separators).
    public var totalTextCount: Int {
        (index.blockCharStarts.last ?? 0) + (index.blockTextCounts.last ?? 0)
    }

    public var plainText: String {
        root.plainText
    }

    public func containsText(_ needle: String) -> Bool {
        root.containsText(needle)
    }

    /// The leaf block whose range contains `position`. Leaf opening Positions
    /// are monotonic (though no longer contiguous — container tokens sit in the
    /// gaps), so this is a binary search. A position exactly on a leaf's opening
    /// token attributes to the previous leaf, matching the original scan.
    /// `index` is the leaf-order index; `node` the leaf; `start` its open token.
    public func blockInfo(containing position: Position) -> BlockInfo? {
        let starts = index.blockStarts
        guard !starts.isEmpty, position >= starts[0], position <= index.endPosition else { return nil }
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= position { low = mid } else { high = mid - 1 }
        }
        let blockIndex = (low > 0 && starts[low] == position) ? low - 1 : low
        return BlockInfo(
            index: blockIndex,
            node: leafNode(blockIndex),
            start: starts[blockIndex],
            path: index.leafPaths[blockIndex]
        )
    }

    /// Whether `position` is the first text position of a leaf that has a
    /// previous sibling in its own container — the precondition for a backward
    /// join into that sibling (see `JoinBlocksStep`). A leaf that is the first
    /// child of its container is lifted, not joined, and is handled separately.
    /// A query, so it stays on Document; `Commands.joinBackward` gates on it.
    public func canJoinBackward(at position: Position) -> Bool {
        guard let info = blockInfo(containing: position) else { return false }
        return (info.path.last ?? 0) > 0 && position == info.start + 1
    }

    /// The Position of the first text character in the block containing
    /// `position` (one past the block's opening boundary).
    public func blockTextStart(at position: Position) -> Position? {
        blockInfo(containing: position).map { $0.start + 1 }
    }

    public func text(from: Position, to: Position) throws -> String {
        guard from <= to else {
            throw StepError.unsupportedReplacement("replacement range must be ordered")
        }
        guard let range = textRange(from: from, to: to) else {
            throw StepError.unsupportedReplacement("replacement range must stay inside one text node")
        }
        return String(range.text[range.range])
    }

    /// Whether the whole `from..<to` range carries `mark`. A query (toolbar
    /// active-state, toggle decisions), so it stays on Document.
    public func rangeHasMark(from: Position, to: Position, mark: Mark) -> Bool {
        guard let range = textRange(from: from, to: to) else { return false }
        return root.textNode(atPath: range.path)?.marks.contains(mark) == true
    }

    /// The Marks carried by the text run spanning `from..<to`, or an empty
    /// list when the range crosses a run boundary.
    public func marks(from: Position, to: Position) -> [Mark] {
        guard let range = textRange(from: from, to: to) else { return [] }
        return root.textNode(atPath: range.path)?.marks ?? []
    }

    /// Locates the text node containing `from...to`: binary search for the
    /// block, then a scan of that block's text runs. Blocks are flat in
    /// slice 1 (paragraph/heading of text runs), so a whole-tree walk here
    /// only added an O(document) term to every edit.
    ///
    /// A shared query: the `rangeHasMark` query and the mark/replace edit
    /// algebra both locate text nodes through here, so it stays on Document
    /// rather than moving into a Step ("where is this text node" is a read).
    func textRange(from: Position, to: Position) -> TextRange? {
        guard let info = blockInfo(containing: from) else { return nil }
        // The full path from the root to the text run: the leaf's container path
        // plus the run's index within the leaf. For a flat document this is just
        // [blockIndex, runIndex], unchanged.
        let leafPath = index.leafPaths[info.index]
        var textStart = info.start + 1
        for (childIndex, child) in info.node.content.enumerated() where child.isText {
            let text = child.text ?? ""
            let textEnd = textStart + text.count
            if from >= textStart, to <= textEnd {
                let startIndex = text.index(text.startIndex, offsetBy: from - textStart)
                let endIndex = text.index(text.startIndex, offsetBy: to - textStart)
                return TextRange(path: leafPath + [childIndex], text: text, range: startIndex..<endIndex)
            }
            textStart = textEnd
        }
        return nil
    }
}

public typealias Position = Int

struct TextRange {
    var path: [Int]
    var text: String
    var range: Range<String.Index>
}

public struct BlockInfo: Equatable, Sendable {
    public var index: Int
    public var node: Node
    public var start: Position
    /// The leaf's child-index path from the root; its last element is the leaf's
    /// index within its own container, and dropping it gives the container path.
    public var path: [Int]

    public init(index: Int, node: Node, start: Position, path: [Int] = []) {
        self.index = index
        self.node = node
        self.start = start
        self.path = path
    }
}
