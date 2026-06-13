import CoreGraphics
import CoreText
import ProseModel

/// Maps between content-space geometry and Positions over a layout tree.
/// Blocks are y-ordered and tile the Position space, so every lookup binary-
/// searches the block first and touches only that block's Line Fragments —
/// these paths run per keystroke and per autoscroll frame, so they must never
/// walk the whole document.
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

        let blocks = root.children
        var rects: [CGRect] = []
        for blockIndex in firstBlockIndex(reaching: lower, in: blocks)..<blocks.count {
            let block = blocks[blockIndex]
            if block.positionRange.lowerBound >= upper { break }
            for line in block.lineFragments {
                let fragment = AbsoluteLineFragment(block: block, line: line)
                let start = max(lower, fragment.absolutePositionRange.lowerBound)
                let end = min(upper, fragment.absolutePositionRange.upperBound)
                guard start < end else { continue }
                let startX = caretOffset(for: start, in: fragment)
                let endX = caretOffset(for: end, in: fragment)
                rects.append(CGRect(
                    x: fragment.absoluteFrame.minX + startX,
                    y: fragment.absoluteFrame.minY,
                    width: endX - startX,
                    height: fragment.absoluteFrame.height
                ))
            }
        }
        return rects
    }

    public func position(after position: Position, in root: LayoutBox) -> Position {
        let blocks = root.children
        guard let index = blockIndex(containing: position, in: blocks),
              isTextPosition(position, in: blocks[index]) else {
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
        guard let index = blockIndex(containing: position, in: blocks),
              isTextPosition(position, in: blocks[index]) else {
            return position
        }
        if position > textRange(of: blocks[index]).lowerBound {
            return position - 1
        }
        guard index > 0 else { return position }
        return textRange(of: blocks[index - 1]).upperBound
    }

    public func position(above position: Position, in root: LayoutBox) -> Position {
        let blocks = root.children
        guard let located = locateLineFragment(containing: position, in: blocks) else {
            return position
        }
        guard let previous = lineFragment(before: located, in: blocks) else {
            // Already on the document's first line.
            return located.absolute(in: blocks).absolutePositionRange.lowerBound
        }
        let x = caretRect(for: position, in: root).minX
        return self.position(closestToX: x, in: previous)
    }

    public func position(below position: Position, in root: LayoutBox) -> Position {
        let blocks = root.children
        guard let located = locateLineFragment(containing: position, in: blocks) else {
            return position
        }
        guard let next = lineFragment(after: located, in: blocks) else {
            // Already on the document's last line.
            return located.absolute(in: blocks).absolutePositionRange.upperBound
        }
        let x = caretRect(for: position, in: root).minX
        return self.position(closestToX: x, in: next)
    }

    // MARK: - Block lookup

    /// The block whose Position range contains `position` (blocks tile the
    /// space, so this is a binary search), or nil when outside every block.
    private func blockIndex(containing position: Position, in blocks: [LayoutBox]) -> Int? {
        guard let first = blocks.first, let last = blocks.last,
              position >= first.positionRange.lowerBound,
              position < last.positionRange.upperBound else { return nil }
        var low = 0
        var high = blocks.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if blocks[mid].positionRange.lowerBound <= position { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// First block whose Position range ends past `position` — where a range
    /// starting at `position` begins intersecting blocks.
    private func firstBlockIndex(reaching position: Position, in blocks: [LayoutBox]) -> Int {
        var low = 0
        var high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].positionRange.upperBound > position { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// The block nearest `y`: the last block starting at or above it (the
    /// answer for a point inside a block or in the gap below it).
    private func blockIndex(nearestToY y: CGFloat, in blocks: [LayoutBox]) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var low = 0
        var high = blocks.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if blocks[mid].frame.minY <= y { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Whether `position` addresses the block's text (including its end) —
    /// the caret-movable positions, as opposed to its boundary tokens.
    private func isTextPosition(_ position: Position, in block: LayoutBox) -> Bool {
        let range = textRange(of: block)
        return range.contains(position) || range.upperBound == position
    }

    private func textRange(of block: LayoutBox) -> Range<Position> {
        (block.positionRange.lowerBound + 1)..<(block.positionRange.upperBound - 1)
    }

    // MARK: - Fragment lookup

    private struct LocatedFragment {
        var blockIndex: Int
        var lineIndex: Int

        func absolute(in blocks: [LayoutBox]) -> AbsoluteLineFragment {
            AbsoluteLineFragment(block: blocks[blockIndex], line: blocks[blockIndex].lineFragments[lineIndex])
        }
    }

    private func locateLineFragment(containing position: Position, in blocks: [LayoutBox]) -> LocatedFragment? {
        guard let blockIdx = blockIndex(containing: position, in: blocks) else { return nil }
        let local = position - blocks[blockIdx].positionRange.lowerBound
        guard let lineIdx = blocks[blockIdx].lineFragments.firstIndex(where: {
            $0.positionRange.contains(local) || $0.positionRange.upperBound == local
        }) else {
            return nil
        }
        return LocatedFragment(blockIndex: blockIdx, lineIndex: lineIdx)
    }

    private func lineFragment(before located: LocatedFragment, in blocks: [LayoutBox]) -> AbsoluteLineFragment? {
        if located.lineIndex > 0 {
            return LocatedFragment(blockIndex: located.blockIndex, lineIndex: located.lineIndex - 1)
                .absolute(in: blocks)
        }
        guard located.blockIndex > 0 else { return nil }
        let block = blocks[located.blockIndex - 1]
        return block.lineFragments.last.map { AbsoluteLineFragment(block: block, line: $0) }
    }

    private func lineFragment(after located: LocatedFragment, in blocks: [LayoutBox]) -> AbsoluteLineFragment? {
        if located.lineIndex + 1 < blocks[located.blockIndex].lineFragments.count {
            return LocatedFragment(blockIndex: located.blockIndex, lineIndex: located.lineIndex + 1)
                .absolute(in: blocks)
        }
        guard located.blockIndex + 1 < blocks.count else { return nil }
        let block = blocks[located.blockIndex + 1]
        return block.lineFragments.first.map { AbsoluteLineFragment(block: block, line: $0) }
    }

    private func lineFragment(containing position: Position, in root: LayoutBox) -> AbsoluteLineFragment? {
        let blocks = root.children
        if let located = locateLineFragment(containing: position, in: blocks) {
            return located.absolute(in: blocks)
        }
        // A boundary token or out-of-range Position: fall back to the
        // document's last line, like the end-of-document caret.
        guard let block = blocks.last, let line = block.lineFragments.last else { return nil }
        return AbsoluteLineFragment(block: block, line: line)
    }

    private func closestLineFragment(to point: CGPoint, in root: LayoutBox) -> AbsoluteLineFragment? {
        let blocks = root.children
        guard let nearest = blockIndex(nearestToY: point.y, in: blocks) else { return nil }
        // Fragment midYs increase monotonically through the document, so the
        // closest one lives in the nearest block or an adjacent one.
        var best: AbsoluteLineFragment?
        var bestDistance = CGFloat.infinity
        for blockIdx in max(0, nearest - 1)...min(blocks.count - 1, nearest + 1) {
            let block = blocks[blockIdx]
            for line in block.lineFragments {
                let distance = abs(line.frame.midY + block.frame.minY - point.y)
                if distance < bestDistance {
                    bestDistance = distance
                    best = AbsoluteLineFragment(block: block, line: line)
                }
            }
        }
        return best
    }

    // MARK: - Within-fragment geometry

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
