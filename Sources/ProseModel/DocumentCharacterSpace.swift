/// "\n"-joined character space: UIKit's text system reasons in plain-text
/// character offsets where every block boundary reads as one "\n", while
/// Positions count two tokens (close + open) per boundary. The conversions
/// live here, on the precomputed block index, so callers (the UITextInput
/// bridge) never re-derive the arithmetic.
extension Document {
    /// The first text Position of the Document (one past the first block's
    /// opening token); the start counterpart of `endTextPosition`.
    public var startTextPosition: Position {
        index.blockStarts.first.map { $0 + 1 } ?? endTextPosition
    }

    /// Plain text between two Positions; block boundaries read as "\n" so
    /// ranges spanning blocks (Select All, tokenizer context) stay readable.
    /// Materializes text only for blocks the range intersects — UIKit's
    /// keyboard asks around every keystroke.
    public func plainText(from: Position, to: Position) -> String {
        var pieces: [String] = []
        guard let firstIndex = firstBlockIndex(withTextEndAtOrAfter: from) else { return "" }
        for blockIndex in firstIndex..<blockCount {
            let textStart = index.blockStarts[blockIndex] + 1
            let count = index.blockTextCounts[blockIndex]
            guard to >= textStart else { break }
            let text = root.content[blockIndex].plainText
            let lower = max(from, textStart)
            let upper = min(to, textStart + count)
            let start = text.index(text.startIndex, offsetBy: lower - textStart)
            let end = text.index(text.startIndex, offsetBy: upper - textStart)
            pieces.append(String(text[start..<end]))
        }
        return pieces.joined(separator: "\n")
    }

    /// Character offset into the "\n"-joined plain text for a Position. A
    /// block boundary is two Positions but reads as one "\n", so Position
    /// arithmetic and string arithmetic drift apart by one per boundary;
    /// UITextInput offset math must stay in character space to agree with
    /// `plainText(from:to:)`. Inverse of `position(atCharacterOffset:)`.
    public func characterOffset(of position: Position) -> Int {
        guard blockCount > 0 else { return 0 }
        guard let blockIndex = firstBlockIndex(withTextEndAtOrAfter: position) else {
            // Past every block: total characters plus one "\n" per boundary.
            return totalTextCount + blockCount - 1
        }
        let textStart = index.blockStarts[blockIndex] + 1
        let charactersBefore = index.blockCharStarts[blockIndex] + blockIndex
        return charactersBefore + max(0, position - textStart)
    }

    /// The Position at a "\n"-joined character offset; the "\n" before a
    /// block maps to the previous block's text end.
    public func position(atCharacterOffset offset: Int) -> Position {
        let count = blockCount
        guard count > 0 else { return endTextPosition }
        // First block whose joined-character end is >= offset.
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if characterEnd(ofBlockAt: mid) >= offset { high = mid } else { low = mid + 1 }
        }
        guard characterEnd(ofBlockAt: low) >= offset else {
            return endTextPosition
        }
        let textStart = index.blockStarts[low] + 1
        let characterStart = index.blockCharStarts[low] + low
        return textStart + max(0, offset - characterStart)
    }

    /// The Position `offset` characters away in "\n"-joined character space,
    /// crossing block boundaries (each one character) as needed.
    public func position(_ position: Position, movedByCharacterOffset offset: Int) -> Position {
        if offset == 0 { return position }
        return offset > 0
            ? self.position(position, movedForwardByCharacterOffset: offset)
            : self.position(position, movedBackwardByCharacterOffset: -offset)
    }

    private func position(_ position: Position, movedForwardByCharacterOffset offset: Int) -> Position {
        var current = position
        var remaining = offset

        while remaining > 0 {
            guard let info = blockInfo(containing: current) else {
                return endTextPosition
            }
            let textStart = info.start + 1
            let textEnd = textStart + index.blockTextCounts[info.index]
            let distanceInsideBlock = max(0, textEnd - current)
            if remaining <= distanceInsideBlock {
                return current + remaining
            }
            remaining -= distanceInsideBlock
            guard info.index + 1 < blockCount else {
                return textEnd
            }
            remaining -= 1
            current = index.blockStarts[info.index + 1] + 1
        }

        return current
    }

    private func position(_ position: Position, movedBackwardByCharacterOffset offset: Int) -> Position {
        var current = position
        var remaining = offset

        while remaining > 0 {
            guard let info = blockInfo(containing: current) else {
                return startTextPosition
            }
            let textStart = info.start + 1
            let distanceInsideBlock = max(0, current - textStart)
            if remaining <= distanceInsideBlock {
                return current - remaining
            }
            remaining -= distanceInsideBlock
            guard info.index > 0 else {
                return textStart
            }
            remaining -= 1
            current = index.blockStarts[info.index - 1] + 1 + index.blockTextCounts[info.index - 1]
        }

        return current
    }

    /// First block whose text end is >= `position`; binary search over the
    /// block index.
    private func firstBlockIndex(withTextEndAtOrAfter position: Position) -> Int? {
        let count = blockCount
        guard count > 0 else { return nil }
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if textEnd(ofBlockAt: mid) >= position { high = mid } else { low = mid + 1 }
        }
        return textEnd(ofBlockAt: low) >= position ? low : nil
    }

    private func textEnd(ofBlockAt blockIndex: Int) -> Position {
        index.blockStarts[blockIndex] + 1 + index.blockTextCounts[blockIndex]
    }

    /// Offset just past the block's text in "\n"-joined character space.
    private func characterEnd(ofBlockAt blockIndex: Int) -> Int {
        index.blockCharStarts[blockIndex] + blockIndex + index.blockTextCounts[blockIndex]
    }
}
