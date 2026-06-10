public struct TextSelection: Codable, Equatable, Sendable {
    public var anchor: Position
    public var head: Position

    public init(anchor: Position, head: Position) {
        self.anchor = anchor
        self.head = head
    }

    public var isCollapsed: Bool {
        anchor == head
    }
}
