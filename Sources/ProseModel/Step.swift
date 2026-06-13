public struct StepApplication: Equatable, Sendable {
    public var document: Document
    public var changedRange: Range<Position>

    public init(document: Document, changedRange: Range<Position>) {
        self.document = document
        self.changedRange = changedRange
    }
}

public protocol Step: Sendable {
    func apply(to document: Document) throws -> StepApplication
    /// The Step that undoes this one, computed against the Document *before*
    /// this Step is applied (history applies inversions in reverse order).
    func inverted(in document: Document) throws -> any Step
    /// Remaps a Position across this Step (CONTEXT glossary: Mapping).
    func map(_ position: Position) -> Position
}

/// Replaces `from..<to` with `insertedText` (carrying `marks`). Within one text
/// run it splices in place; across a run or block boundary it merges the end
/// blocks into one. Built on the block-replace primitive — the algebra behind
/// `ReplaceStep`.
private func replacingText(in document: Document, from: Position, to: Position, with insertedText: String, marks: [Mark]) throws -> Document {
    guard let range = document.textRange(from: from, to: to) else {
        // The range crosses a run or block boundary; merge across it.
        return try replacingAcrossRuns(in: document, from: from, to: to, with: insertedText, marks: marks)
    }
    let blockIndex = range.path[0]
    if !marks.isEmpty, from == to, range.path.count == 2 {
        let offset = range.text.distance(from: range.text.startIndex, to: range.range.lowerBound)
        let newRoot = document.root.splicingTextNode(
            atPath: range.path,
            replacing: offset..<offset,
            withText: insertedText,
            marks: marks
        )
        return document.replacingBlocks(in: blockIndex..<(blockIndex + 1), with: [newRoot.content[blockIndex]])
    }
    var updated = range.text
    updated.replaceSubrange(range.range, with: insertedText)
    let newRoot = document.root.replacingTextNode(atPath: range.path, with: updated)
    guard range.path.count == 2 else { return Document(newRoot) }
    return document.replacingBlocks(in: blockIndex..<(blockIndex + 1), with: [newRoot.content[blockIndex]])
}

/// Replacement whose range crosses a text-run or block boundary: the blocks at
/// the ends merge into one block of the first's type, keeping the runs outside
/// the range — ProseMirror's replace semantics. This is what Backspace at a
/// block start becomes when the keyboard deletes the boundary "\n" in character
/// space, and what typing over a selection spanning blocks does.
private func replacingAcrossRuns(in document: Document, from: Position, to: Position, with insertedText: String, marks: [Mark]) throws -> Document {
    guard from <= to,
          let fromInfo = document.blockInfo(containing: from),
          let toInfo = document.blockInfo(containing: to),
          fromInfo.index <= toInfo.index else {
        throw StepError.unsupportedReplacement("replacement range must lie within the document's text")
    }
    let head = fromInfo.node.inlineRuns(upTo: from - (fromInfo.start + 1))
    let tail = toInfo.node.inlineRuns(from: to - (toInfo.start + 1))
    let inserted: [Node] = insertedText.isEmpty ? [] : [.text(insertedText, marks: marks)]
    let merged = fromInfo.node.withContent(head + inserted + tail)
    return document.replacingBlocks(in: fromInfo.index..<(toInfo.index + 1), with: [merged])
}

public struct ReplaceStep: Step, Codable, Equatable, Sendable {
    public var from: Position
    public var to: Position
    public var insertText: String
    /// Marks applied to the inserted text — the pending typing Marks at a
    /// collapsed caret. Empty means the insertion joins the surrounding run.
    public var insertMarks: [Mark]

    public init(from: Position, to: Position, insertText: String, insertMarks: [Mark] = []) {
        self.from = from
        self.to = to
        self.insertText = insertText
        self.insertMarks = insertMarks
    }

    public func apply(to document: Document) throws -> StepApplication {
        let replaced = try replacingText(in: document, from: from, to: to, with: insertText, marks: insertMarks)
        return StepApplication(
            document: replaced,
            changedRange: from..<max(from + insertText.count, from + 1)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        let deleted = try document.text(from: from, to: to)
        return ReplaceStep(from: from, to: from + insertText.count, insertText: deleted)
    }

    public func map(_ position: Position) -> Position {
        if position <= from {
            return position
        }
        if position >= to {
            return position + insertText.count - (to - from)
        }
        return from + insertText.count
    }

    private enum CodingKeys: String, CodingKey {
        case from, to, insertText, insertMarks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(Position.self, forKey: .from)
        to = try container.decode(Position.self, forKey: .to)
        insertText = try container.decode(String.self, forKey: .insertText)
        insertMarks = try container.decodeIfPresent([Mark].self, forKey: .insertMarks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(insertText, forKey: .insertText)
        if !insertMarks.isEmpty {
            try container.encode(insertMarks, forKey: .insertMarks)
        }
    }
}

public enum StepError: Error, Equatable, CustomStringConvertible {
    case unsupportedReplacement(String)

    public var description: String {
        switch self {
        case .unsupportedReplacement(let message):
            message
        }
    }
}

/// Adds or removes `mark` over `from..<to`, which must stay inside one text
/// node, splitting the run so surrounding text keeps its Marks. The shared
/// algebra behind both mark Steps, built on the block-replace primitive.
private func settingMark(in document: Document, from: Position, to: Position, mark: Mark, enabled: Bool) throws -> Document {
    guard let range = document.textRange(from: from, to: to) else {
        throw StepError.unsupportedReplacement("mark range must stay inside one text node")
    }
    let existing = document.root.textNode(atPath: range.path)?.marks ?? []
    let updated = enabled
        ? MarkRules.adding(mark, to: existing)
        : existing.filter { $0 != mark }
    let lower = range.text.distance(from: range.text.startIndex, to: range.range.lowerBound)
    let upper = range.text.distance(from: range.text.startIndex, to: range.range.upperBound)
    let newRoot = document.root.splicingTextNode(
        atPath: range.path,
        replacing: lower..<upper,
        withText: String(range.text[range.range]),
        marks: updated
    )
    guard range.path.count == 2 else { return Document(newRoot) }
    return document.replacingBlocks(in: range.path[0]..<(range.path[0] + 1), with: [newRoot.content[range.path[0]]])
}

public struct AddMarkStep: Step, Codable, Equatable, Sendable {
    public var from: Position
    public var to: Position
    public var mark: Mark

    public init(from: Position, to: Position, mark: Mark) {
        self.from = from
        self.to = to
        self.mark = mark
    }

    public func apply(to document: Document) throws -> StepApplication {
        StepApplication(document: try settingMark(in: document, from: from, to: to, mark: mark, enabled: true), changedRange: from..<to)
    }

    public func inverted(in document: Document) throws -> any Step {
        RemoveMarkStep(from: from, to: to, mark: mark)
    }

    public func map(_ position: Position) -> Position {
        position
    }
}

public struct RemoveMarkStep: Step, Codable, Equatable, Sendable {
    public var from: Position
    public var to: Position
    public var mark: Mark

    public init(from: Position, to: Position, mark: Mark) {
        self.from = from
        self.to = to
        self.mark = mark
    }

    public func apply(to document: Document) throws -> StepApplication {
        StepApplication(document: try settingMark(in: document, from: from, to: to, mark: mark, enabled: false), changedRange: from..<to)
    }

    public func inverted(in document: Document) throws -> any Step {
        AddMarkStep(from: from, to: to, mark: mark)
    }

    public func map(_ position: Position) -> Position {
        position
    }
}
