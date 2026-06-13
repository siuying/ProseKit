public enum Origin: String, Codable, Equatable, Sendable {
    case local
    case remote
    case history
}

public struct Transaction: Sendable {
    public var steps: [any Step]
    public var selection: TextSelection
    public var origin: Origin

    public init(steps: [any Step], selection: TextSelection, origin: Origin) {
        self.steps = steps
        self.selection = selection
        self.origin = origin
    }

    public func apply(to document: Document) throws -> AppliedTransaction {
        var current = document
        var changedRange: Range<Position>?
        for step in steps {
            let applied = try step.apply(to: current)
            if let existing = changedRange {
                let mapping = Mapping([step])
                let mapped = mapping.map(existing.lowerBound)..<mapping.map(existing.upperBound)
                changedRange = union(mapped, applied.changedRange)
            } else {
                changedRange = applied.changedRange
            }
            current = applied.document
        }
        return AppliedTransaction(
            document: current,
            selection: selection,
            origin: origin,
            changedRange: changedRange ?? selection.head..<selection.head
        )
    }
}

public struct AppliedTransaction: Equatable, Sendable {
    public var document: Document
    public var selection: TextSelection
    public var origin: Origin
    public var changedRange: Range<Position>

    public init(document: Document, selection: TextSelection, origin: Origin, changedRange: Range<Position>) {
        self.document = document
        self.selection = selection
        self.origin = origin
        self.changedRange = changedRange
    }
}

private func union(_ lhs: Range<Position>, _ rhs: Range<Position>) -> Range<Position> {
    min(lhs.lowerBound, rhs.lowerBound)..<max(lhs.upperBound, rhs.upperBound)
}
