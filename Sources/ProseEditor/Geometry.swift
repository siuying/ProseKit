import CoreGraphics
import ProseModel

public struct GeometryMapper: Sendable {
    public var characterWidth: CGFloat

    public init(characterWidth: CGFloat = 10) {
        self.characterWidth = characterWidth
    }

    public func closestPosition(to point: CGPoint, in root: LayoutBox) -> Position {
        guard let fragment = closestLineFragment(to: point, in: root) else {
            return root.positionRange.lowerBound
        }
        let column = max(0, min(fragment.text.count, Int((point.x / characterWidth).rounded())))
        return fragment.positionRange.lowerBound + column
    }

    public func caretRect(for position: Position, in root: LayoutBox) -> CGRect {
        guard let fragment = lineFragment(containing: position, in: root) else {
            return .zero
        }
        let column = max(0, min(fragment.text.count, position - fragment.positionRange.lowerBound))
        return CGRect(
            x: CGFloat(column) * characterWidth,
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
            let x = CGFloat(start - fragment.positionRange.lowerBound) * characterWidth
            let width = CGFloat(end - start) * characterWidth
            return CGRect(x: x, y: fragment.frame.minY, width: width, height: fragment.frame.height)
        }
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
