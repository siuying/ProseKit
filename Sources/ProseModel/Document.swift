public struct Document: Codable, Hashable, Sendable {
    public private(set) var root: Node

    /// Per-block position and character arithmetic is precomputed once per
    /// Document. Documents are immutable — editing produces a new Document —
    /// so the index cannot go stale, and the paths UIKit hammers between
    /// keystrokes (text(in:), offset math, blockInfo) stay O(log blocks)
    /// instead of re-walking the tree per call.
    private struct BlockIndex: Hashable, Sendable {
        /// blockStarts[i] is the Position of block i's opening token.
        var blockStarts: [Position]
        /// blockTextCounts[i] is block i's plainText character count.
        var blockTextCounts: [Int]
        /// blockCharStarts[i] is the sum of plainText counts before block i.
        var blockCharStarts: [Int]
        /// Position just past the last block (root.nodeSize - 1).
        var endPosition: Position
        var endTextPosition: Position
    }

    private var index: BlockIndex

    public init(_ root: Node) {
        self.root = root
        self.index = Self.makeIndex(of: root)
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

    private static func makeIndex(of root: Node) -> BlockIndex {
        var starts: [Position] = []
        var textCounts: [Int] = []
        var charStarts: [Int] = []
        starts.reserveCapacity(root.content.count)
        textCounts.reserveCapacity(root.content.count)
        charStarts.reserveCapacity(root.content.count)
        var position: Position = 1
        var characters = 0
        for block in root.content {
            starts.append(position)
            charStarts.append(characters)
            let count = block.plainText.count
            textCounts.append(count)
            characters += count
            position += block.nodeSize
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
            endPosition: position,
            endTextPosition: endTextPosition
        )
    }

    public var blockCount: Int {
        index.blockStarts.count
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

    /// Blocks tile the position space contiguously, so this is a binary
    /// search. A block-boundary position (end of block i == start of block
    /// i+1) belongs to block i, matching the original first-match scan.
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
        return BlockInfo(index: blockIndex, node: root.content[blockIndex], start: starts[blockIndex])
    }

    public func splitBlock(at position: Position) throws -> (Document, TextSelection, Range<Position>) {
        guard let info = blockInfo(containing: position),
              info.node.type == "paragraph" || info.node.type == "heading" else {
            throw StepError.unsupportedReplacement("splitBlock requires a text block")
        }
        let textStart = info.start + 1
        let offset = max(0, min(info.node.plainText.count, position - textStart))
        let text = info.node.plainText
        let splitIndex = text.index(text.startIndex, offsetBy: offset)
        let before = String(text[..<splitIndex])
        let after = String(text[splitIndex...])
        let first = info.node.withContent([.text(before)])
        let second = info.node.withContent([.text(after)])
        var blocks = root.content
        blocks.replaceSubrange(info.index...info.index, with: [first, second])
        let newBlockStart = info.start + first.nodeSize
        let changedRange = info.start..<(newBlockStart + second.nodeSize)
        return (
            Document(.doc(blocks)),
            TextSelection(anchor: newBlockStart + 1, head: newBlockStart + 1),
            changedRange
        )
    }

    public func joinBackward(at position: Position) throws -> (Document, TextSelection, Range<Position>)? {
        guard let info = blockInfo(containing: position), info.index > 0, position == info.start + 1 else {
            return nil
        }
        var blocks = root.content
        let previous = blocks[info.index - 1]
        let current = blocks[info.index]
        let previousTextEnd = info.start - 1

        if current.plainText.isEmpty {
            blocks.remove(at: info.index)
        } else {
            blocks[info.index - 1] = previous.withContent([.text(previous.plainText + current.plainText)])
            blocks.remove(at: info.index)
        }

        return (
            Document(.doc(blocks)),
            TextSelection(anchor: previousTextEnd, head: previousTextEnd),
            previousTextEnd - previous.nodeSize + 1..<(previousTextEnd + current.nodeSize)
        )
    }

    public func togglingHeading(at position: Position, level: Int) throws -> (Document, TextSelection, Range<Position>) {
        guard let info = blockInfo(containing: position) else {
            throw StepError.unsupportedReplacement("toggleHeading requires a text block")
        }
        var blocks = root.content
        blocks[info.index] = info.node.type == "heading" ? info.node.asParagraph() : info.node.asHeading(level: level)
        return (
            Document(.doc(blocks)),
            TextSelection(anchor: position, head: position),
            info.start..<(info.start + blocks[info.index].nodeSize)
        )
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

    public func replacingText(from: Position, to: Position, with insertedText: String, marks: [Mark] = []) throws -> Document {
        guard let range = textRange(from: from, to: to) else {
            throw StepError.unsupportedReplacement("replacement range must stay inside one text node")
        }
        if !marks.isEmpty, from == to, range.path.count == 2 {
            return Document(root.replacingTextNodeWithMarkedInsertion(
                atPath: range.path,
                offset: range.text.distance(from: range.text.startIndex, to: range.range.lowerBound),
                insertedText: insertedText,
                marks: marks
            ))
        }
        var updated = range.text
        updated.replaceSubrange(range.range, with: insertedText)
        return Document(root.replacingTextNode(atPath: range.path, with: updated))
    }

    public func addingMark(from: Position, to: Position, mark: Mark) throws -> Document {
        try settingMark(from: from, to: to, mark: mark, enabled: true)
    }

    public func removingMark(from: Position, to: Position, mark: Mark) throws -> Document {
        try settingMark(from: from, to: to, mark: mark, enabled: false)
    }

    public func rangeHasMark(from: Position, to: Position, mark: Mark) -> Bool {
        guard let range = textRange(from: from, to: to) else { return false }
        return root.textNode(atPath: range.path)?.marks.contains(mark) == true
    }

    private func settingMark(from: Position, to: Position, mark: Mark, enabled: Bool) throws -> Document {
        guard let range = textRange(from: from, to: to) else {
            throw StepError.unsupportedReplacement("mark range must stay inside one text node")
        }
        return Document(root.settingMark(
            atPath: range.path,
            lowerOffset: range.text.distance(from: range.text.startIndex, to: range.range.lowerBound),
            upperOffset: range.text.distance(from: range.text.startIndex, to: range.range.upperBound),
            mark: mark,
            enabled: enabled
        ))
    }

    private func textRange(from: Position, to: Position) -> TextRange? {
        var found: TextRange?
        root.walkTextNodes(start: 0, path: []) { path, textStart, text in
            guard found == nil else { return }
            let textEnd = textStart + text.count
            guard from >= textStart, to <= textEnd else { return }
            let startIndex = text.index(text.startIndex, offsetBy: from - textStart)
            let endIndex = text.index(text.startIndex, offsetBy: to - textStart)
            found = TextRange(path: path, text: text, range: startIndex..<endIndex)
        }
        return found
    }
}

public typealias Position = Int

private struct TextRange {
    var path: [Int]
    var text: String
    var range: Range<String.Index>
}

public struct BlockInfo: Equatable, Sendable {
    public var index: Int
    public var node: Node
    public var start: Position

    public init(index: Int, node: Node, start: Position) {
        self.index = index
        self.node = node
        self.start = start
    }
}

private extension Node {
    func containsText(_ needle: String) -> Bool {
        if isText {
            return text?.contains(needle) ?? false
        }
        return content.contains { $0.containsText(needle) }
    }

    func walkTextNodes(start: Position, path: [Int], visit: ([Int], Position, String) -> Void) {
        if isText {
            visit(path, start, text ?? "")
            return
        }

        var position = start + 1
        for (index, child) in content.enumerated() {
            child.walkTextNodes(start: position, path: path + [index], visit: visit)
            position += child.nodeSize
        }
    }

    func replacingTextNode(atPath path: [Int], with text: String) -> Node {
        guard let index = path.first else {
            var copy = self
            copy.text = text
            return copy
        }

        var copy = self
        copy.content[index] = copy.content[index].replacingTextNode(
            atPath: Array(path.dropFirst()),
            with: text
        )
        return copy
    }

    func replacingTextNodeWithMarkedInsertion(atPath path: [Int], offset: Int, insertedText: String, marks: [Mark]) -> Node {
        guard path.count == 2 else { return self }
        var copy = self
        let blockIndex = path[0]
        let textIndex = path[1]
        let original = copy.content[blockIndex].content[textIndex]
        let text = original.text ?? ""
        let split = text.index(text.startIndex, offsetBy: offset)
        var replacement: [Node] = []
        let before = String(text[..<split])
        let after = String(text[split...])
        if !before.isEmpty {
            replacement.append(.text(before, marks: original.marks))
        }
        if !insertedText.isEmpty {
            replacement.append(.text(insertedText, marks: marks))
        }
        if !after.isEmpty {
            replacement.append(.text(after, marks: original.marks))
        }
        copy.content[blockIndex].content.replaceSubrange(textIndex...textIndex, with: replacement)
        return copy
    }

    func settingMark(atPath path: [Int], lowerOffset: Int, upperOffset: Int, mark: Mark, enabled: Bool) -> Node {
        guard path.count == 2 else { return self }
        var copy = self
        let blockIndex = path[0]
        let textIndex = path[1]
        let original = copy.content[blockIndex].content[textIndex]
        let text = original.text ?? ""
        let lower = text.index(text.startIndex, offsetBy: lowerOffset)
        let upper = text.index(text.startIndex, offsetBy: upperOffset)
        var replacement: [Node] = []

        func marks(_ existing: [Mark]) -> [Mark] {
            if enabled {
                return existing.contains(mark) ? existing : existing + [mark]
            }
            return existing.filter { $0 != mark }
        }

        let before = String(text[..<lower])
        let marked = String(text[lower..<upper])
        let after = String(text[upper...])
        if !before.isEmpty {
            replacement.append(.text(before, marks: original.marks))
        }
        if !marked.isEmpty {
            replacement.append(.text(marked, marks: marks(original.marks)))
        }
        if !after.isEmpty {
            replacement.append(.text(after, marks: original.marks))
        }
        copy.content[blockIndex].content.replaceSubrange(textIndex...textIndex, with: replacement)
        return copy
    }

    func textNode(atPath path: [Int]) -> Node? {
        guard path.count == 2,
              content.indices.contains(path[0]),
              content[path[0]].content.indices.contains(path[1]) else {
            return nil
        }
        return content[path[0]].content[path[1]]
    }
}
