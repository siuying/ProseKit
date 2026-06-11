import CoreGraphics
import CoreText
import ProseModel

public struct GeometryMapper: Sendable {
    public init() {}

    public func closestPosition(to point: CGPoint, in root: LayoutBox) -> Position {
        guard let fragment = closestLineFragment(to: point, in: root) else {
            return root.positionRange.lowerBound
        }
        return position(closestToX: point.x, in: fragment)
    }

    public func caretRect(for position: Position, in root: LayoutBox) -> CGRect {
        guard let fragment = lineFragment(containing: position, in: root) else {
            return .zero
        }
        return CGRect(
            x: fragment.absoluteFrame.minX + caretOffset(for: position, in: fragment),
            y: fragment.absoluteFrame.minY,
            width: 2,
            height: fragment.absoluteFrame.height
        )
    }

    public func selectionRects(for selection: TextSelection, in root: LayoutBox) -> [CGRect] {
        let lower = min(selection.anchor, selection.head)
        let upper = max(selection.anchor, selection.head)
        guard lower < upper else { return [] }

        return lineFragments(in: root).compactMap { fragment in
            let start = max(lower, fragment.absolutePositionRange.lowerBound)
            let end = min(upper, fragment.absolutePositionRange.upperBound)
            guard start < end else { return nil }
            let startX = caretOffset(for: start, in: fragment)
            let endX = caretOffset(for: end, in: fragment)
            return CGRect(
                x: fragment.absoluteFrame.minX + startX,
                y: fragment.absoluteFrame.minY,
                width: endX - startX,
                height: fragment.absoluteFrame.height
            )
        }
    }

    public func position(after position: Position, in root: LayoutBox) -> Position {
        let blocks = root.children
        guard let index = blocks.firstIndex(where: {
            textRange(of: $0).contains(position) || textRange(of: $0).upperBound == position
        }) else {
            return position
        }
        if position < textRange(of: blocks[index]).upperBound {
            return position + 1
        }
        guard blocks.indices.contains(index + 1) else { return position }
        return textRange(of: blocks[index + 1]).lowerBound
    }

    public func position(before position: Position, in root: LayoutBox) -> Position {
        let blocks = root.children
        guard let index = blocks.firstIndex(where: {
            textRange(of: $0).contains(position) || textRange(of: $0).upperBound == position
        }) else {
            return position
        }
        if position > textRange(of: blocks[index]).lowerBound {
            return position - 1
        }
        guard index > 0 else { return position }
        return textRange(of: blocks[index - 1]).upperBound
    }

    public func position(above position: Position, in root: LayoutBox) -> Position {
        let fragments = lineFragments(in: root)
        guard let index = fragments.firstIndex(where: {
            $0.absolutePositionRange.contains(position) || $0.absolutePositionRange.upperBound == position
        }) else {
            return position
        }
        guard index > 0 else {
            return fragments.first?.absolutePositionRange.lowerBound ?? position
        }
        let x = caretRect(for: position, in: root).minX
        return self.position(closestToX: x, in: fragments[index - 1])
    }

    public func position(below position: Position, in root: LayoutBox) -> Position {
        let fragments = lineFragments(in: root)
        guard let index = fragments.firstIndex(where: {
            $0.absolutePositionRange.contains(position) || $0.absolutePositionRange.upperBound == position
        }) else {
            return position
        }
        guard index + 1 < fragments.count else {
            return fragments.last?.absolutePositionRange.upperBound ?? position
        }
        let x = caretRect(for: position, in: root).minX
        return self.position(closestToX: x, in: fragments[index + 1])
    }

    private func textRange(of block: LayoutBox) -> Range<Position> {
        (block.positionRange.lowerBound + 1)..<(block.positionRange.upperBound - 1)
    }

    private func position(closestToX x: CGFloat, in fragment: AbsoluteLineFragment) -> Position {
        guard let typeset = fragment.line.typesetLine else {
            return fragment.absolutePositionRange.lowerBound
        }
        let utf16Index = CTLineGetStringIndexForPosition(
            typeset.line,
            CGPoint(x: x - fragment.absoluteFrame.minX, y: 0)
        )
        guard utf16Index != kCFNotFound else {
            return fragment.absolutePositionRange.lowerBound
        }
        let clamped = max(typeset.utf16Range.lowerBound, min(utf16Index, typeset.utf16Range.upperBound))
        let index = characterIndex(forUTF16Offset: clamped - typeset.utf16Range.lowerBound, in: fragment.line.text)
        return fragment.absolutePositionRange.lowerBound + fragment.line.text.distance(from: fragment.line.text.startIndex, to: index)
    }

    private func caretOffset(for position: Position, in fragment: AbsoluteLineFragment) -> CGFloat {
        guard let typeset = fragment.line.typesetLine else { return 0 }
        let characterOffset = max(0, min(fragment.line.text.count, position - fragment.absolutePositionRange.lowerBound))
        let utf16Offset = fragment.line.text.prefix(characterOffset).utf16.count
        return CGFloat(CTLineGetOffsetForStringIndex(
            typeset.line,
            typeset.utf16Range.lowerBound + utf16Offset,
            nil
        ))
    }

    private func closestLineFragment(to point: CGPoint, in root: LayoutBox) -> AbsoluteLineFragment? {
        lineFragments(in: root)
            .min { abs($0.absoluteFrame.midY - point.y) < abs($1.absoluteFrame.midY - point.y) }
    }

    private func lineFragment(containing position: Position, in root: LayoutBox) -> AbsoluteLineFragment? {
        let fragments = lineFragments(in: root)
        return fragments.first {
            $0.absolutePositionRange.contains(position) || $0.absolutePositionRange.upperBound == position
        } ?? fragments.last
    }

    private func lineFragments(in root: LayoutBox) -> [AbsoluteLineFragment] {
        root.children.flatMap { block in
            block.lineFragments.map { line in
                AbsoluteLineFragment(block: block, line: line)
            }
        }
    }
}

private struct AbsoluteLineFragment {
    var block: LayoutBox
    var line: LineFragment

    var absoluteFrame: CGRect {
        line.frame.offsetBy(dx: block.frame.minX, dy: block.frame.minY)
    }

    var absolutePositionRange: Range<Position> {
        (block.positionRange.lowerBound + line.positionRange.lowerBound)
            ..< (block.positionRange.lowerBound + line.positionRange.upperBound)
    }
}
