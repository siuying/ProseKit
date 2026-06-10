public enum Origin: String, Codable, Equatable, Sendable {
    case local
    case remote
    case history
}

public struct Transaction: Sendable {
    public var steps: [ReplaceStep]
    public var selection: TextSelection
    public var origin: Origin

    public init(steps: [ReplaceStep], selection: TextSelection, origin: Origin) {
        self.steps = steps
        self.selection = selection
        self.origin = origin
    }

    public func apply(to document: Document) throws -> AppliedTransaction {
        var current = document
        for step in steps {
            current = try step.apply(to: current).document
        }
        return AppliedTransaction(document: current, selection: selection, origin: origin)
    }
}

public struct AppliedTransaction: Equatable, Sendable {
    public var document: Document
    public var selection: TextSelection
    public var origin: Origin

    public init(document: Document, selection: TextSelection, origin: Origin) {
        self.document = document
        self.selection = selection
        self.origin = origin
    }
}
