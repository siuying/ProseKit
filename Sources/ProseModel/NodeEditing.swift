/// Low-level `Node` manipulation primitives shared across the module: the
/// Document queries (`containsText`, `rangeHasMark`) and the Steps' edit algebra
/// (mark splice, run cut, text-node replace) both build on these. Internal —
/// not part of any module's public interface.
extension Node {
    func containsText(_ needle: String) -> Bool {
        if isText {
            return text?.contains(needle) ?? false
        }
        return content.contains { $0.containsText(needle) }
    }

    func replacingTextNode(atPath path: [Int], with text: String) -> Node {
        guard let index = path.first else {
            var copy = self
            copy.text = text
            return copy
        }

        var copy = self
        copy.content[index] = copy.content[index].replacingTextNode(
            atPath: Array(path.dropFirst()),
            with: text
        )
        return copy
    }

    /// Replaces `range` (character offsets) of the text node at `path` with a
    /// run of `middle` carrying `middleMarks`, keeping the surrounding text in
    /// runs that retain the original Marks. Empty runs are dropped. The one
    /// splice behind both marked insertion and mark add/remove.
    func splicingTextNode(atPath path: [Int], replacing range: Range<Int>, withText middle: String, marks middleMarks: [Mark]) -> Node {
        guard let first = path.first else { return self }
        var copy = self
        guard path.count == 1 else {
            // Descend toward the leaf block holding the text run.
            copy.content[first] = copy.content[first].splicingTextNode(
                atPath: Array(path.dropFirst()),
                replacing: range,
                withText: middle,
                marks: middleMarks
            )
            return copy
        }
        // `first` is the text-run index within this leaf block.
        let textIndex = first
        let original = copy.content[textIndex]
        let text = original.text ?? ""
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        var replacement: [Node] = []
        let before = String(text[..<lower])
        let after = String(text[upper...])
        if !before.isEmpty {
            replacement.append(.text(before, marks: original.marks))
        }
        if !middle.isEmpty {
            replacement.append(.text(middle, marks: middleMarks))
        }
        if !after.isEmpty {
            replacement.append(.text(after, marks: original.marks))
        }
        copy.content.replaceSubrange(textIndex...textIndex, with: replacement)
        return copy
    }

    /// The text runs covering the block's first `offset` characters, Marks
    /// preserved; the run straddling the cut is split.
    func inlineRuns(upTo offset: Int) -> [Node] {
        var runs: [Node] = []
        var remaining = max(0, min(plainText.count, offset))
        for child in content where child.isText {
            guard remaining > 0 else { break }
            let text = child.text ?? ""
            if text.count <= remaining {
                if !text.isEmpty {
                    runs.append(child)
                }
                remaining -= text.count
            } else {
                let cut = text.index(text.startIndex, offsetBy: remaining)
                runs.append(.text(String(text[..<cut]), marks: child.marks))
                remaining = 0
            }
        }
        return runs
    }

    /// The text runs from the block's character `offset` to its end, Marks
    /// preserved; the run straddling the cut is split.
    func inlineRuns(from offset: Int) -> [Node] {
        var runs: [Node] = []
        var remaining = max(0, min(plainText.count, offset))
        for child in content where child.isText {
            let text = child.text ?? ""
            if remaining >= text.count {
                remaining -= text.count
                continue
            }
            if remaining > 0 {
                let cut = text.index(text.startIndex, offsetBy: remaining)
                runs.append(.text(String(text[cut...]), marks: child.marks))
                remaining = 0
            } else if !text.isEmpty {
                runs.append(child)
            }
        }
        return runs
    }

    func textNode(atPath path: [Int]) -> Node? {
        guard let first = path.first, content.indices.contains(first) else { return nil }
        if path.count == 1 {
            return content[first].isText ? content[first] : nil
        }
        return content[first].textNode(atPath: Array(path.dropFirst()))
    }
}
