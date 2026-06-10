public struct Mapping: Sendable {
    public var steps: [ReplaceStep]

    public init(_ steps: [ReplaceStep] = []) {
        self.steps = steps
    }

    public func map(_ position: Position) -> Position {
        steps.reduce(position) { mapped, step in
            step.map(mapped)
        }
    }
}
