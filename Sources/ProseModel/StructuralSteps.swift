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
        try document.splitBlock(at: at, blockType: blockType, blockAttrs: blockAttrs)
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

/// Joins the block whose first text position is `at` into the previous block:
/// an empty block is removed, a non-empty one merges its text into the
/// predecessor (what Backspace at a block start does).
public struct JoinBlocksStep: Step, Codable, Equatable, Sendable {
    public var at: Position

    public init(at: Position) {
        self.at = at
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let application = document.joinBackward(at: at) else {
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
