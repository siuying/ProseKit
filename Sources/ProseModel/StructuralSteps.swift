/// Splits the text block containing `position` at it into two blocks. The
/// second block inherits the first's type and Attrs unless `blockType` /
/// `blockAttrs` override it (how a join inverts back to the original block).
/// Built on the block-replace primitive.
private func splitBlock(
    in document: Document,
    at position: Position,
    blockType: String?,
    blockAttrs: [String: JSONValue]?
) throws -> StepApplication {
    guard let info = document.blockInfo(containing: position),
          info.node.type == "paragraph" || info.node.type == "heading" else {
        throw StepError.unsupportedReplacement("splitBlock requires a text block")
    }
    let textStart = info.start + 1
    let offset = max(0, min(info.node.plainText.count, position - textStart))
    let text = info.node.plainText
    let splitIndex = text.index(text.startIndex, offsetBy: offset)
    let first = info.node.withContent([.text(String(text[..<splitIndex]))])
    let second = blockType
        .map { Node(type: $0, attrs: blockAttrs ?? [:], content: [.text(String(text[splitIndex...]))]) }
        ?? info.node.withContent([.text(String(text[splitIndex...]))])
    let newBlockStart = info.start + first.nodeSize
    // Split within the leaf's own container (the root, for a flat document).
    let childIndex = info.path.last ?? info.index
    let parentPath = Array(info.path.dropLast())
    return StepApplication(
        document: document.replacingBlocks(at: parentPath, childRange: childIndex..<(childIndex + 1), with: [first, second]),
        changedRange: info.start..<(newBlockStart + second.nodeSize)
    )
}

/// Splits the text block containing `at` into two blocks at that Position.
/// The second block inherits the first's type and Attrs unless `blockType` /
/// `blockAttrs` override it (how a join inverts back to the original block).
public struct SplitBlockStep: Step, Codable, Equatable, Sendable {
    public var at: Position
    public var blockType: String?
    public var blockAttrs: [String: JSONValue]?

    public init(at: Position, blockType: String? = nil, blockAttrs: [String: JSONValue]? = nil) {
        self.at = at
        self.blockType = blockType
        self.blockAttrs = blockAttrs
    }

    public func apply(to document: Document) throws -> StepApplication {
        try splitBlock(in: document, at: at, blockType: blockType, blockAttrs: blockAttrs)
    }

    public func inverted(in document: Document) throws -> any Step {
        // The split inserts a close+open token pair at `at`; the new block's
        // first text position is therefore at + 2, which is where a join undoes it.
        JoinBlocksStep(at: at + 2)
    }

    /// A split inserts two boundary tokens at `at`; everything from `at` on
    /// shifts past them (the caret at the split point lands in the new block).
    public func map(_ position: Position) -> Position {
        position < at ? position : position + 2
    }
}

/// Joins the block whose first text position is `position` into the previous
/// block: an empty block is removed, a non-empty one merges its runs into the
/// predecessor (Marks preserved). Returns nil when `position` is not the start
/// of a non-first block. Built on the block-replace primitive.
private func joinBackward(in document: Document, at position: Position) -> StepApplication? {
    guard let info = document.blockInfo(containing: position), position == info.start + 1 else {
        return nil
    }
    // Join into the previous sibling within the leaf's own container. A leaf
    // that is the first child of its container has no previous sibling — it is
    // lifted out, not joined (handled by the lift path), so bail here.
    let childIndex = info.path.last ?? info.index
    guard childIndex > 0 else { return nil }
    let parentPath = Array(info.path.dropLast())
    let parent = document.node(atPath: parentPath)
    let previous = parent.content[childIndex - 1]
    let current = parent.content[childIndex]
    // The previous sibling must be a textblock to absorb this block's runs;
    // merging into a container is a different operation (not slice 03).
    guard previous.isTextblock else { return nil }
    let previousTextEnd = info.start - 1

    let joined: Document
    if document.textCount(ofBlockAt: info.index) == 0 {
        joined = document.replacingBlocks(at: parentPath, childRange: childIndex..<(childIndex + 1), with: [])
    } else {
        // Concatenating the runs (not the plain text) keeps both blocks'
        // Marks across the join; coalescing adjacent same-Mark runs normalizes
        // like ProseMirror, so a join inverts a split exactly.
        let merged = previous.withContent(Node.coalescedRuns(previous.content + current.content))
        joined = document.replacingBlocks(at: parentPath, childRange: (childIndex - 1)..<(childIndex + 1), with: [merged])
    }

    return StepApplication(
        document: joined,
        changedRange: previousTextEnd - previous.nodeSize + 1..<(previousTextEnd + current.nodeSize)
    )
}

/// Joins the block whose first text position is `at` into the previous block:
/// an empty block is removed, a non-empty one merges its text into the
/// predecessor (what Backspace at a block start does).
public struct JoinBlocksStep: Step, Codable, Equatable, Sendable {
    public var at: Position

    public init(at: Position) {
        self.at = at
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let application = joinBackward(in: document, at: at) else {
            throw StepError.unsupportedReplacement("joinBackward requires the start of a non-first block")
        }
        return application
    }

    public func inverted(in document: Document) throws -> any Step {
        guard let info = document.blockInfo(containing: at) else {
            throw StepError.unsupportedReplacement("joinBackward requires the start of a non-first block")
        }
        // Re-split at the previous block's text end, restoring the joined
        // block's type and Attrs (a merge inherits the predecessor's otherwise).
        return SplitBlockStep(at: at - 2, blockType: info.node.type, blockAttrs: info.node.attrs)
    }

    /// The join removes the two boundary tokens just before `at`; positions
    /// past them shift back, and the deleted tokens map to the merge point.
    public func map(_ position: Position) -> Position {
        position <= at - 2 ? position : max(at - 2, position - 2)
    }
}

/// Sets the block at `position` to a heading of `level`, or a paragraph when
/// `level` is nil. Toggling (heading back to paragraph) is a Command decision
/// layered on top; this only sets. Built on the block-replace primitive.
private func settingBlockType(in document: Document, at position: Position, headingLevel level: Int?) throws -> StepApplication {
    guard let info = document.blockInfo(containing: position) else {
        throw StepError.unsupportedReplacement("setBlockType requires a text block")
    }
    let updated = level.map(info.node.asHeading(level:)) ?? info.node.asParagraph()
    return StepApplication(
        document: document.replacingBlocks(in: info.index..<(info.index + 1), with: [updated]),
        changedRange: info.start..<(info.start + updated.nodeSize)
    )
}

/// Sets the block containing `at` to a heading of `headingLevel`, or to a
/// paragraph when it is nil. Block sizes are unchanged, so Positions are stable.
public struct SetBlockTypeStep: Step, Codable, Equatable, Sendable {
    public var at: Position
    public var headingLevel: Int?

    public init(at: Position, headingLevel: Int?) {
        self.at = at
        self.headingLevel = headingLevel
    }

    public func apply(to document: Document) throws -> StepApplication {
        try settingBlockType(in: document, at: at, headingLevel: headingLevel)
    }

    public func inverted(in document: Document) throws -> any Step {
        let node = document.blockInfo(containing: at)?.node
        let level = node?.type == "heading" ? node?.attrs["level"]?.intValue : nil
        return SetBlockTypeStep(at: at, headingLevel: level)
    }

    public func map(_ position: Position) -> Position {
        position
    }
}

/// Sets (or clears) the `textAlign` Attr on the block at `position`. Only
/// paragraph and heading carry it (Q9.2); `nil` or `"left"` clears it, keeping
/// the absent-means-left default rather than storing a redundant Attr.
private func settingTextAlign(in document: Document, at position: Position, to value: String?) throws -> StepApplication {
    guard let info = document.blockInfo(containing: position),
          info.node.type == "paragraph" || info.node.type == "heading" else {
        throw StepError.unsupportedReplacement("textAlign applies to paragraph and heading")
    }
    var updated = info.node
    if let value, value != "left" {
        updated.attrs["textAlign"] = .string(value)
    } else {
        updated.attrs["textAlign"] = nil
    }
    return StepApplication(
        document: document.replacingBlocks(in: info.index..<(info.index + 1), with: [updated]),
        changedRange: info.start..<(info.start + updated.nodeSize)
    )
}

/// Sets (or clears, when nil/"left") the `textAlign` Attr on the block
/// containing `at`. Attrs carry no size, so Positions are stable.
public struct SetTextAlignStep: Step, Codable, Equatable, Sendable {
    public var at: Position
    public var value: String?

    public init(at: Position, value: String?) {
        self.at = at
        self.value = value
    }

    public func apply(to document: Document) throws -> StepApplication {
        try settingTextAlign(in: document, at: at, to: value)
    }

    public func inverted(in document: Document) throws -> any Step {
        SetTextAlignStep(at: at, value: document.blockInfo(containing: at)?.node.attrs["textAlign"]?.stringValue)
    }

    public func map(_ position: Position) -> Position {
        position
    }
}

/// Wraps the single block whose node range is `blockRange` into a new container
/// of `containerType` (e.g. a paragraph into a blockquote). The block keeps its
/// content; a container open/close token pair is added around it.
public struct WrapInStep: Step, Codable, Equatable, Sendable {
    public var blockRange: Range<Position>
    public var containerType: String

    public init(blockRange: Range<Position>, containerType: String) {
        self.blockRange = blockRange
        self.containerType = containerType
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: blockRange.lowerBound + 1),
              info.start == blockRange.lowerBound else {
            throw StepError.unsupportedReplacement("wrap requires the block at the given range")
        }
        let childIndex = info.path.last ?? info.index
        let parentPath = Array(info.path.dropLast())
        let wrapper = Node(type: containerType, content: [info.node])
        return StepApplication(
            document: document.replacingBlocks(at: parentPath, childRange: childIndex..<(childIndex + 1), with: [wrapper]),
            changedRange: info.start..<(info.start + wrapper.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        // After wrapping, the block sits one Position deeper (past the new
        // container's opening token); lifting it there restores the original.
        LiftStep(blockRange: (blockRange.lowerBound + 1)..<(blockRange.upperBound + 1))
    }

    /// Wrap inserts the container's opening token before the block and its
    /// closing token after it.
    public func map(_ position: Position) -> Position {
        if position <= blockRange.lowerBound { return position }
        if position < blockRange.upperBound { return position + 1 }
        return position + 2
    }
}

/// Lifts the block whose node range is `blockRange` — which must be the first
/// child of its container — out to the container's own parent, before the
/// container. If it was the container's only child, the now-empty container is
/// removed; otherwise the container keeps its remaining children.
public struct LiftStep: Step, Codable, Equatable, Sendable {
    public var blockRange: Range<Position>

    public init(blockRange: Range<Position>) {
        self.blockRange = blockRange
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: blockRange.lowerBound + 1),
              info.start == blockRange.lowerBound,
              (info.path.last ?? 0) == 0, info.path.count >= 2 else {
            throw StepError.unsupportedReplacement("lift requires the first child of a container")
        }
        let containerPath = Array(info.path.dropLast())
        let container = document.node(atPath: containerPath)
        let grandparentPath = Array(containerPath.dropLast())
        let containerIndex = containerPath.last ?? 0
        let leaf = container.content[0]
        let remaining = Array(container.content.dropFirst())
        let replacement = remaining.isEmpty ? [leaf] : [leaf, container.withContent(remaining)]
        let containerStart = info.start - 1
        return StepApplication(
            document: document.replacingBlocks(
                at: grandparentPath,
                childRange: containerIndex..<(containerIndex + 1),
                with: replacement
            ),
            changedRange: containerStart..<(containerStart + container.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        guard let info = document.blockInfo(containing: blockRange.lowerBound + 1) else {
            throw StepError.unsupportedReplacement("lift requires the first child of a container")
        }
        // The container we are lifting out of; re-wrapping into its type, at the
        // block's lifted-up Position (one shallower), inverts the lift.
        let containerType = document.node(atPath: Array(info.path.dropLast())).type
        return WrapInStep(
            blockRange: (blockRange.lowerBound - 1)..<(blockRange.upperBound - 1),
            containerType: containerType
        )
    }

    /// Lifting moves the block up one level, dropping the enclosing opening
    /// token that preceded it.
    public func map(_ position: Position) -> Position {
        if position <= blockRange.lowerBound { return position }
        if position < blockRange.upperBound { return position - 1 }
        return position
    }
}
