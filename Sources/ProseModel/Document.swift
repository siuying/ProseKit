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

private extension Node {
    var plainText: String {
        if isText {
            return text ?? ""
        }
        return content.map(\.plainText).joined()
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
