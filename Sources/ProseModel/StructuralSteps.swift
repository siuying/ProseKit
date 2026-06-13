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

/// Position of the node at `path` (root-to-node child indices). The root's
/// direct children start at Position 1; each container opening token advances
/// one Position before its children.
private func nodeStart(atPath path: [Int], in document: Document) -> Position? {
    guard !path.isEmpty else { return 0 }
    var node = document.root
    var position: Position = 1
    for (depth, childIndex) in path.enumerated() {
        guard node.content.indices.contains(childIndex) else { return nil }
        for siblingIndex in 0..<childIndex {
            position += node.content[siblingIndex].nodeSize
        }
        let child = node.content[childIndex]
        if depth == path.count - 1 {
            return position
        }
        position += 1
        node = child
    }
    return nil
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

/// Splits the list item containing `at` at the textblock boundary implied by
/// the caret, creating a new sibling list item. This is the list-aware Enter
/// operation: the paragraph content is split like `SplitBlockStep`, but the
/// structural replacement happens in the enclosing list container.
public struct SplitListItemStep: Step, Codable, Equatable, Sendable {
    public var at: Position

    public init(at: Position) {
        self.at = at
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: at),
              info.node.type == "paragraph" || info.node.type == "heading",
              info.path.count >= 3 else {
            throw StepError.unsupportedReplacement("splitListItem requires a text block inside a list item")
        }

        let itemPath = Array(info.path.dropLast())
        let listPath = Array(itemPath.dropLast())
        let blockIndex = info.path.last ?? 0
        let itemIndex = itemPath.last ?? 0
        let item = document.node(atPath: itemPath)
        let list = document.node(atPath: listPath)
        guard item.type == "listItem", list.type == "bulletList" else {
            throw StepError.unsupportedReplacement("splitListItem requires a bullet list item")
        }

        let textStart = info.start + 1
        let offset = max(0, min(info.node.plainText.count, at - textStart))
        let firstBlock = info.node.withContent(Node.coalescedRuns(info.node.inlineRuns(upTo: offset)))
        let secondBlock = info.node.withContent(Node.coalescedRuns(info.node.inlineRuns(from: offset)))
        let beforeBlocks = Array(item.content.prefix(blockIndex))
        let afterBlocks = Array(item.content.dropFirst(blockIndex + 1))
        let firstItem = item.withContent(beforeBlocks + [firstBlock])
        let secondItem = item.withContent([secondBlock] + afterBlocks)
        let itemStart = nodeStart(atPath: itemPath, in: document) ?? info.start
        let changedEnd = itemStart + firstItem.nodeSize + secondItem.nodeSize

        return StepApplication(
            document: document.replacingBlocks(
                at: listPath,
                childRange: itemIndex..<(itemIndex + 1),
                with: [firstItem, secondItem]
            ),
            changedRange: itemStart..<changedEnd
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        JoinListItemsStep(at: map(at))
    }

    /// Splitting one list item into two inserts the close/open pair for the
    /// two item containers plus the close/open pair for the split textblock.
    public func map(_ position: Position) -> Position {
        position < at ? position : position + 4
    }
}

/// Joins the list item whose first textblock starts at `at` into its previous
/// sibling item, merging the previous item's last textblock with the current
/// item's first textblock and preserving any remaining blocks.
public struct JoinListItemsStep: Step, Codable, Equatable, Sendable {
    public var at: Position

    public init(at: Position) {
        self.at = at
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: at),
              at == info.start + 1,
              info.path.count >= 3 else {
            throw StepError.unsupportedReplacement("joinListItems requires the start of a list item's first text block")
        }

        let itemPath = Array(info.path.dropLast())
        let listPath = Array(itemPath.dropLast())
        let blockIndex = info.path.last ?? 0
        let itemIndex = itemPath.last ?? 0
        let item = document.node(atPath: itemPath)
        let list = document.node(atPath: listPath)
        guard item.type == "listItem", list.type == "bulletList", blockIndex == 0, itemIndex > 0 else {
            throw StepError.unsupportedReplacement("joinListItems requires a non-first bullet list item")
        }

        let previousItem = list.content[itemIndex - 1]
        guard let previousLast = previousItem.content.last,
              previousLast.isTextblock, info.node.isTextblock else {
            throw StepError.unsupportedReplacement("joinListItems requires adjacent text blocks")
        }

        let mergedBlock = previousLast.withContent(Node.coalescedRuns(previousLast.content + info.node.content))
        let previousPrefix = previousItem.content.dropLast()
        let currentTail = item.content.dropFirst()
        let mergedItem = previousItem.withContent(Array(previousPrefix) + [mergedBlock] + Array(currentTail))
        let previousPath = listPath + [itemIndex - 1]
        let previousStart = nodeStart(atPath: previousPath, in: document) ?? info.start

        return StepApplication(
            document: document.replacingBlocks(
                at: listPath,
                childRange: (itemIndex - 1)..<(itemIndex + 1),
                with: [mergedItem]
            ),
            changedRange: previousStart..<(previousStart + previousItem.nodeSize + item.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        SplitListItemStep(at: at - 4)
    }

    /// Joining two list items removes the same four boundary tokens that
    /// `SplitListItemStep` inserted; positions in the removed boundary clamp to
    /// the merge point.
    public func map(_ position: Position) -> Position {
        position <= at - 4 ? position : max(at - 4, position - 4)
    }
}

/// Lifts the list item containing `at` out of its enclosing bullet list. The
/// item contents become siblings of the list, and any preceding/following items
/// stay wrapped in valid bulletList containers.
public struct LiftListItemStep: Step, Codable, Equatable, Sendable {
    public var at: Position

    public init(at: Position) {
        self.at = at
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: at),
              at == info.start + 1,
              info.path.count >= 3 else {
            throw StepError.unsupportedReplacement("liftListItem requires the start of a list item's first text block")
        }

        let itemPath = Array(info.path.dropLast())
        let listPath = Array(itemPath.dropLast())
        let blockIndex = info.path.last ?? 0
        let itemIndex = itemPath.last ?? 0
        let item = document.node(atPath: itemPath)
        let list = document.node(atPath: listPath)
        guard item.type == "listItem", list.type == "bulletList", blockIndex == 0 else {
            throw StepError.unsupportedReplacement("liftListItem requires a bullet list item")
        }

        let preceding = Array(list.content.prefix(itemIndex))
        let following = Array(list.content.dropFirst(itemIndex + 1))
        var replacement: [Node] = []
        if !preceding.isEmpty {
            replacement.append(list.withContent(preceding))
        }
        replacement.append(contentsOf: item.content)
        if !following.isEmpty {
            replacement.append(list.withContent(following))
        }

        let grandparentPath = Array(listPath.dropLast())
        let listIndex = listPath.last ?? 0
        let listStart = nodeStart(atPath: listPath, in: document) ?? info.start
        return StepApplication(
            document: document.replacingBlocks(
                at: grandparentPath,
                childRange: listIndex..<(listIndex + 1),
                with: replacement
            ),
            changedRange: listStart..<(listStart + list.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        guard let info = document.blockInfo(containing: at),
              info.path.count >= 3 else {
            throw StepError.unsupportedReplacement("liftListItem requires a list item")
        }
        let itemPath = Array(info.path.dropLast())
        let listPath = Array(itemPath.dropLast())
        let itemIndex = itemPath.last ?? 0
        let item = document.node(atPath: itemPath)
        let list = document.node(atPath: listPath)
        guard item.type == "listItem", list.type == "bulletList" else {
            throw StepError.unsupportedReplacement("liftListItem requires a bullet list item")
        }
        let preceding = itemIndex > 0
        let following = itemIndex < list.content.count - 1
        let precedingSize = preceding ? list.withContent(Array(list.content.prefix(itemIndex))).nodeSize : 0
        let listStart = nodeStart(atPath: listPath, in: document) ?? info.start
        let firstLiftedBlockStart = listStart + precedingSize
        return WrapLiftedListItemStep(
            at: firstLiftedBlockStart + 1,
            blockCount: item.content.count,
            itemAttrs: item.attrs,
            mergeWithPreviousList: preceding,
            mergeWithNextList: following
        )
    }

    /// The item's first block moves two Positions shallower: past the removed
    /// listItem and child block opening tokens.
    public func map(_ position: Position) -> Position {
        position < at ? position : max(at - 2, position - 2)
    }
}

/// Inverse of `LiftListItemStep`: wraps the lifted block siblings back into a
/// list item and rejoins adjacent list fragments that the lift split apart.
public struct WrapLiftedListItemStep: Step, Codable, Equatable, Sendable {
    public var at: Position
    public var blockCount: Int
    public var itemAttrs: [String: JSONValue]
    public var mergeWithPreviousList: Bool
    public var mergeWithNextList: Bool

    public init(
        at: Position,
        blockCount: Int,
        itemAttrs: [String: JSONValue] = [:],
        mergeWithPreviousList: Bool,
        mergeWithNextList: Bool
    ) {
        self.at = at
        self.blockCount = blockCount
        self.itemAttrs = itemAttrs
        self.mergeWithPreviousList = mergeWithPreviousList
        self.mergeWithNextList = mergeWithNextList
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard blockCount > 0,
              let info = document.blockInfo(containing: at) else {
            throw StepError.unsupportedReplacement("wrapLiftedListItem requires lifted block content")
        }
        let parentPath = Array(info.path.dropLast())
        let firstBlockIndex = info.path.last ?? 0
        let parent = document.node(atPath: parentPath)
        guard firstBlockIndex + blockCount <= parent.content.count else {
            throw StepError.unsupportedReplacement("wrapLiftedListItem block range exceeds parent")
        }

        let liftedBlocks = Array(parent.content[firstBlockIndex..<(firstBlockIndex + blockCount)])
        var items: [Node] = []
        var rangeStart = firstBlockIndex
        var rangeEnd = firstBlockIndex + blockCount

        if mergeWithPreviousList {
            guard firstBlockIndex > 0, parent.content[firstBlockIndex - 1].type == "bulletList" else {
                throw StepError.unsupportedReplacement("wrapLiftedListItem requires a previous bullet list")
            }
            rangeStart -= 1
            items.append(contentsOf: parent.content[firstBlockIndex - 1].content)
        }

        items.append(Node(type: "listItem", attrs: itemAttrs, content: liftedBlocks))

        if mergeWithNextList {
            guard rangeEnd < parent.content.count, parent.content[rangeEnd].type == "bulletList" else {
                throw StepError.unsupportedReplacement("wrapLiftedListItem requires a following bullet list")
            }
            items.append(contentsOf: parent.content[rangeEnd].content)
            rangeEnd += 1
        }

        let list = Node(type: "bulletList", content: items)
        let changedStart = nodeStart(atPath: parentPath + [rangeStart], in: document) ?? info.start
        return StepApplication(
            document: document.replacingBlocks(
                at: parentPath,
                childRange: rangeStart..<rangeEnd,
                with: [list]
            ),
            changedRange: changedStart..<(changedStart + list.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        LiftListItemStep(at: map(at))
    }

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

/// Wraps one textblock in a one-item list (`bulletList > listItem > block`).
/// The block keeps its inline content; the list and item boundary tokens are
/// added around it.
public struct WrapInListStep: Step, Codable, Equatable, Sendable {
    public var blockRange: Range<Position>
    public var listType: String
    public var itemType: String

    public init(blockRange: Range<Position>, listType: String, itemType: String = "listItem") {
        self.blockRange = blockRange
        self.listType = listType
        self.itemType = itemType
    }

    public func apply(to document: Document) throws -> StepApplication {
        guard let info = document.blockInfo(containing: blockRange.lowerBound + 1),
              info.start == blockRange.lowerBound else {
            throw StepError.unsupportedReplacement("wrapInList requires the block at the given range")
        }
        let childIndex = info.path.last ?? info.index
        let parentPath = Array(info.path.dropLast())
        let item = Node(type: itemType, content: [info.node])
        let list = Node(type: listType, content: [item])
        return StepApplication(
            document: document.replacingBlocks(
                at: parentPath,
                childRange: childIndex..<(childIndex + 1),
                with: [list]
            ),
            changedRange: info.start..<(info.start + list.nodeSize)
        )
    }

    public func inverted(in document: Document) throws -> any Step {
        LiftListItemStep(at: blockRange.lowerBound + 3)
    }

    public func map(_ position: Position) -> Position {
        if position <= blockRange.lowerBound { return position }
        if position < blockRange.upperBound { return position + 2 }
        return position + 4
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
