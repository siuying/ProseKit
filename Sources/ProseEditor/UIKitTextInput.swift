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

    // `UITextRange` is an `NSObject`, so `==` (and `XCTAssertEqual`) route through
    // `isEqual(_:)`, which defaults to pointer identity. Two ranges over the same
    // anchor/head are the same selection, so compare by value.
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ProseTextRange else { return false }
        return anchor == other.anchor && head == other.head
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(anchor)
        hasher.combine(head)
        return hasher.finalize()
    }
}

public final class ProseTextSelectionRect: UITextSelectionRect {
    private let rectValue: CGRect
    private let containsStartValue: Bool
    private let containsEndValue: Bool

    public init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
        self.rectValue = rect
        self.containsStartValue = containsStart
        self.containsEndValue = containsEnd
    }

    public override var rect: CGRect { rectValue }
    public override var writingDirection: NSWritingDirection { .leftToRight }
    public override var containsStart: Bool { containsStartValue }
    public override var containsEnd: Bool { containsEndValue }
    public override var isVertical: Bool { false }
}
#endif
