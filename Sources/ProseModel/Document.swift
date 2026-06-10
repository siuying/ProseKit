public struct Document: Codable, Hashable, Sendable {
    public var root: Node

    public init(_ root: Node) {
        self.root = root
    }

    public init(from decoder: Decoder) throws {
        root = try Node(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try root.encode(to: encoder)
    }

    public var endPosition: Int {
        root.nodeSize - 1
    }

    public var endTextPosition: Position {
        var position = endPosition
        root.walkTextNodes(start: 0, path: []) { _, textStart, text in
            position = textStart + text.count
        }
        return position
    }

    public func position(ofBlockAt blockIndex: Int) -> Position? {
        guard root.content.indices.contains(blockIndex) else { return nil }
        return 1 + root.content[..<blockIndex].reduce(0) { $0 + $1.nodeSize }
    }

    public func position(ofTextInBlockAt blockIndex: Int) -> Position? {
        position(ofBlockAt: blockIndex).map { $0 + 1 }
    }

    public var plainText: String {
        root.plainText
    }

    public func containsText(_ needle: String) -> Bool {
        root.containsText(needle)
    }

    public func blockInfo(containing position: Position) -> BlockInfo? {
        var start = 1
        for (index, block) in root.content.enumerated() {
            let end = start + block.nodeSize
            if position >= start, position <= end {
                return BlockInfo(index: index, node: block, start: start)
            }
            start = end
        }
        return nil
    }

    public func splitBlock(at position: Position) throws -> (Document, TextSelection) {
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
        return (Document(.doc(blocks)), TextSelection(anchor: newBlockStart + 1, head: newBlockStart + 1))
    }

    public func joinBackward(at position: Position) throws -> (Document, TextSelection)? {
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
            TextSelection(anchor: previousTextEnd, head: previousTextEnd)
        )
    }

    public func togglingHeading(at position: Position, level: Int) throws -> (Document, TextSelection) {
        guard let info = blockInfo(containing: position) else {
            throw StepError.unsupportedReplacement("toggleHeading requires a text block")
        }
        var blocks = root.content
        blocks[info.index] = info.node.type == "heading" ? info.node.asParagraph() : info.node.asHeading(level: level)
        return (Document(.doc(blocks)), TextSelection(anchor: position, head: position))
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

    public func replacingText(from: Position, to: Position, with insertedText: String) throws -> Document {
        guard let range = textRange(from: from, to: to) else {
            throw StepError.unsupportedReplacement("replacement range must stay inside one text node")
        }
        var updated = range.text
        updated.replaceSubrange(range.range, with: insertedText)
        return Document(root.replacingTextNode(atPath: range.path, with: updated))
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
}
