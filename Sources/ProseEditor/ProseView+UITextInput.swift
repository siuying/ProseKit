#if canImport(UIKit)
import ProseModel
import UIKit

/// The UITextInput bridge: positions, ranges, and geometry for the system's
/// text interaction. Character-offset arithmetic lives on Document (the
/// "\n"-joined character space); geometry questions go to the GeometryMapper.
extension ProseView {
    public var selectedTextRange: UITextRange? {
        get { ProseTextRange(anchor: state.selection.anchor, head: state.selection.head) }
        set {
            guard let range = newValue as? ProseTextRange else { return }
            let selection = range.textSelection
            guard selection != state.selection else { return }
            inputDelegate?.selectionWillChange(self)
            core.setSelection(selection)
            // No canvas repaint: the Canvas draws no selection-dependent
            // content (the caret and selection overlay are the system's
            // UITextInteraction chrome), so a selection change leaves every
            // painted pixel identical. UITextInteraction drives setSelectedText
            // Range many times a second during a drag, and a full-Viewport
            // repaint per call was choppy on the simulator.
            inputDelegate?.selectionDidChange(self)
            onStateChange?()
        }
    }

    public var markedTextRange: UITextRange? { nil }

    public var beginningOfDocument: UITextPosition {
        ProseTextPosition(state.document.startTextPosition)
    }

    public var endOfDocument: UITextPosition {
        ProseTextPosition(state.document.endTextPosition)
    }

    public var tokenizer: UITextInputTokenizer {
        proseTokenizer
    }

    public func text(in range: UITextRange) -> String? {
        guard let range = range as? ProseTextRange else { return nil }
        return state.document.plainText(
            from: min(range.anchor, range.head),
            to: max(range.anchor, range.head)
        )
    }

    public func replace(_ range: UITextRange, withText text: String) {
        guard let range = range as? ProseTextRange else { return }
        // Adopt the range as the selection, then insert: autocorrect and
        // dictation get the same newline segmentation (and pending typing
        // Marks at a collapsed caret) as typed text.
        core.setSelection(range.textSelection)
        insertText(text)
    }

    public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        if let markedText {
            // Provisional IME composition: never run shortcuts until the text is
            // committed (which arrives via insertText, not setMarkedText).
            insertText(markedText, applyInputRules: false)
        }
    }

    public func unmarkText() {}

    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = fromPosition as? ProseTextPosition, let to = toPosition as? ProseTextPosition else {
            return nil
        }
        return ProseTextRange(anchor: from.position, head: to.position)
    }

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? ProseTextPosition else { return nil }
        return ProseTextPosition(clamp(state.document.position(position.position, movedByCharacterOffset: offset)))
    }

    public func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        guard let position = position as? ProseTextPosition, let layoutBox else { return nil }
        var current = position.position
        for _ in 0..<offset {
            switch direction {
            case .left: current = geometryMapper.position(before: current, in: layoutBox)
            case .right: current = geometryMapper.position(after: current, in: layoutBox)
            case .up: current = geometryMapper.position(above: current, in: layoutBox)
            case .down: current = geometryMapper.position(below: current, in: layoutBox)
            @unknown default: return nil
            }
        }
        return ProseTextPosition(clamp(current))
    }

    public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let lhs = position as? ProseTextPosition, let rhs = other as? ProseTextPosition else {
            return .orderedSame
        }
        if lhs.position == rhs.position { return .orderedSame }
        return lhs.position < rhs.position ? .orderedAscending : .orderedDescending
    }

    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let from = from as? ProseTextPosition, let to = toPosition as? ProseTextPosition else {
            return 0
        }
        return state.document.characterOffset(of: to.position) - state.document.characterOffset(of: from.position)
    }

    public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        direction == .left || direction == .up ? range.start : range.end
    }

    public func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let position = position as? ProseTextPosition,
              let end = self.position(from: position, offset: direction == .left ? -1 : 1) as? ProseTextPosition else {
            return nil
        }
        return ProseTextRange(anchor: position.position, head: end.position)
    }

    public func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    public func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    public func firstRect(for range: UITextRange) -> CGRect {
        guard let range = range as? ProseTextRange else { return .zero }
        guard let layoutBox,
              let first = geometryMapper.selectionRects(for: range.textSelection, in: layoutBox).first else {
            return caretRect(for: ProseTextPosition(min(range.anchor, range.head)))
        }
        return first
    }

    public func caretRect(for position: UITextPosition) -> CGRect {
        guard let position = position as? ProseTextPosition, let layoutBox else { return .zero }
        return geometryMapper.caretRect(for: position.position, in: layoutBox)
    }

    public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let range = range as? ProseTextRange, let layoutBox else { return [] }
        let rects = geometryMapper.selectionRects(for: range.textSelection, in: layoutBox)
        return rects.enumerated().map { index, rect in
            ProseTextSelectionRect(
                rect: rect,
                containsStart: index == 0,
                containsEnd: index == rects.count - 1
            )
        }
    }

    public func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let layoutBox else {
            return ProseTextPosition(state.selection.head)
        }
        return ProseTextPosition(clamp(geometryMapper.closestPosition(to: point, in: layoutBox)))
    }

    public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        closestPosition(to: point)
    }

    public func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point) as? ProseTextPosition else { return nil }
        return ProseTextRange(anchor: position.position, head: clamp(position.position + 1))
    }
}
#endif
