import CoreGraphics
import CoreText
import ProseModel

public struct GeometryMapper: Sendable {
    public init() {}

    public func closestPosition(to point: CGPoint, in root: LayoutBox) -> Position {
        guard let fragment = closestLineFragment(to: point, in: root) else {
            return root.positionRange.lowerBound
        }
        guard let typeset = fragment.typesetLine else {
            return fragment.positionRange.lowerBound
        }
        let utf16Index = CTLineGetStringIndexForPosition(
            typeset.line,
            CGPoint(x: point.x - fragment.frame.minX, y: 0)
        )
        guard utf16Index != kCFNotFound else {
            return fragment.positionRange.lowerBound
        }
        let clamped = max(typeset.utf16Range.lowerBound, min(utf16Index, typeset.utf16Range.upperBound))
        let index = characterIndex(forUTF16Offset: clamped - typeset.utf16Range.lowerBound, in: fragment.text)
        return fragment.positionRange.lowerBound + fragment.text.distance(from: fragment.text.startIndex, to: index)
    }

    public func caretRect(for position: Position, in root: LayoutBox) -> CGRect {
        guard let fragment = lineFragment(containing: position, in: root) else {
            return .zero
        }
        return CGRect(
            x: fragment.frame.minX + caretOffset(for: position, in: fragment),
            y: fragment.frame.minY,
            width: 2,
            height: fragment.frame.height
        )
    }

    public func selectionRects(for selection: TextSelection, in root: LayoutBox) -> [CGRect] {
        let lower = min(selection.anchor, selection.head)
        let upper = max(selection.anchor, selection.head)
        guard lower < upper else { return [] }

        return root.children.flatMap(\.lineFragments).compactMap { fragment in
            let start = max(lower, fragment.positionRange.lowerBound)
            let end = min(upper, fragment.positionRange.upperBound)
            guard start < end else { return nil }
            let startX = caretOffset(for: start, in: fragment)
            let endX = caretOffset(for: end, in: fragment)
            return CGRect(
                x: fragment.frame.minX + startX,
                y: fragment.frame.minY,
                width: endX - startX,
                height: fragment.frame.height
            )
        }
    }

    private func caretOffset(for position: Position, in fragment: LineFragment) -> CGFloat {
        guard let typeset = fragment.typesetLine else { return 0 }
        let characterOffset = max(0, min(fragment.text.count, position - fragment.positionRange.lowerBound))
        let utf16Offset = fragment.text.prefix(characterOffset).utf16.count
        return CGFloat(CTLineGetOffsetForStringIndex(
            typeset.line,
            typeset.utf16Range.lowerBound + utf16Offset,
            nil
        ))
    }

    private func closestLineFragment(to point: CGPoint, in root: LayoutBox) -> LineFragment? {
        root.children
            .flatMap(\.lineFragments)
            .min { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }
    }

    private func lineFragment(containing position: Position, in root: LayoutBox) -> LineFragment? {
        let fragments = root.children.flatMap(\.lineFragments)
        return fragments.first {
            $0.positionRange.contains(position) || $0.positionRange.upperBound == position
        } ?? fragments.last
    }
}
