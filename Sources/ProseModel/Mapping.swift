public struct Mapping: Sendable {
    public var steps: [any Step]

    public init(_ steps: [any Step] = []) {
        self.steps = steps
    }

    public func map(_ position: Position) -> Position {
        steps.reduce(position) { mapped, step in
            step.map(mapped)
        }
    }
}
