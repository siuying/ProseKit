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
    func inverted(in document: Document) throws -> ReplaceStep
    func map(_ position: Position) -> Position
}

public struct ReplaceStep: Step, Codable, Equatable, Sendable {
    public var from: Position
    public var to: Position
    public var insertText: String

    public init(from: Position, to: Position, insertText: String) {
        self.from = from
        self.to = to
        self.insertText = insertText
    }

    public func apply(to document: Document) throws -> StepApplication {
        let replaced = try document.replacingText(from: from, to: to, with: insertText)
        return StepApplication(
            document: replaced,
            changedRange: from..<max(from + insertText.count, from + 1)
        )
    }

    public func inverted(in document: Document) throws -> ReplaceStep {
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
