#if canImport(UIKit)
import UIKit
import ProseModel

public final class ProseTextPosition: UITextPosition {
    public let position: Position

    public init(_ position: Position) {
        self.position = position
    }
}

public final class ProseTextRange: UITextRange {
    public let anchor: Position
    public let head: Position

    public init(anchor: Position, head: Position) {
        self.anchor = anchor
        self.head = head
    }

    public override var start: UITextPosition {
        ProseTextPosition(min(anchor, head))
    }

    public override var end: UITextPosition {
        ProseTextPosition(max(anchor, head))
    }

    public override var isEmpty: Bool {
        anchor == head
    }

    public var textSelection: TextSelection {
        TextSelection(anchor: anchor, head: head)
    }
}
#endif
