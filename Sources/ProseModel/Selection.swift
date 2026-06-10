public protocol Selection: Sendable {
    var anchor: Position { get }
    var head: Position { get }
}

public struct TextSelection: Selection, Codable, Equatable, Sendable {
    public var anchor: Position
    public var head: Position

    public init(anchor: Position, head: Position) {
        self.anchor = anchor
        self.head = head
    }

    public var isCollapsed: Bool {
        anchor == head
    }

    public func mapped(through mapping: Mapping) -> TextSelection {
        TextSelection(anchor: mapping.map(anchor), head: mapping.map(head))
    }
}
