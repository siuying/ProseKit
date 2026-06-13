import ProseModel

public struct Command: Sendable {
    private let body: @Sendable (inout EditorState) throws -> Bool

    public init(_ body: @escaping @Sendable (inout EditorState) throws -> Bool) {
        self.body = body
    }

    public func run(in state: inout EditorState) throws -> Bool {
        try body(&state)
    }
}

/// Commands decide *what* edit to make — reading the state, choosing Steps,
/// and placing the Selection — then dispatch a Transaction. The Document only
/// applies Steps; it never chooses.
public enum Commands {
    private static func isListType(_ type: String) -> Bool {
        type == "bulletList" || type == "orderedList" || type == "taskList"
    }

    private static func itemType(forListType type: String) -> String {
        type == "taskList" ? "taskItem" : "listItem"
    }

    private static func listType(_ listType: String, acceptsItemType itemType: String) -> Bool {
        itemType == self.itemType(forListType: listType)
    }

    public static func splitBlock() -> Command {
        Command { state in
            guard state.selection.isCollapsed else { return false }
            let step: any Step
            if let info = state.document.blockInfo(containing: state.selection.head),
               info.path.count >= 3 {
                let itemPath = Array(info.path.dropLast())
                let listPath = Array(itemPath.dropLast())
                let item = state.document.node(atPath: itemPath)
                let list = state.document.node(atPath: listPath)
                if listType(list.type, acceptsItemType: item.type), isListType(list.type) {
                    step = info.node.plainText.isEmpty && state.selection.head == info.start + 1
                        ? LiftListItemStep(at: state.selection.head)
                        : SplitListItemStep(at: state.selection.head)
                } else {
                    step = SplitBlockStep(at: state.selection.head)
                }
            } else {
                step = SplitBlockStep(at: state.selection.head)
            }
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
                origin: .local
            ))
            return true
        }
    }

    public static func joinBackward() -> Command {
        Command { state in
            guard state.selection.isCollapsed else {
                return false
            }
            let step: any Step
            if let info = state.document.blockInfo(containing: state.selection.head),
               state.selection.head == info.start + 1,
               info.path.count >= 3 {
                let itemPath = Array(info.path.dropLast())
                let listPath = Array(itemPath.dropLast())
                let item = state.document.node(atPath: itemPath)
                let list = state.document.node(atPath: listPath)
                if listType(list.type, acceptsItemType: item.type), isListType(list.type),
                   (itemPath.last ?? 0) > 0, (info.path.last ?? 0) == 0 {
                    step = JoinListItemsStep(at: state.selection.head)
                } else if state.document.canJoinBackward(at: state.selection.head) {
                    step = JoinBlocksStep(at: state.selection.head)
                } else {
                    return false
                }
            } else if state.document.canJoinBackward(at: state.selection.head) {
                step = JoinBlocksStep(at: state.selection.head)
            } else {
                return false
            }
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
                origin: .local
            ))
            return true
        }
    }

    /// Lifts the block at the caret out of its container, when the caret is at
    /// the text start of the container's first child (Backspace there unwraps,
    /// rather than joining — there is no previous sibling to join into).
    public static func liftOutOfContainer() -> Command {
        Command { state in
            guard state.selection.isCollapsed,
                  let info = state.document.blockInfo(containing: state.selection.head),
                  state.selection.head == info.start + 1,
                  (info.path.last ?? 0) == 0,
                  info.path.count >= 2 else {
                return false
            }
            let container = state.document.node(atPath: Array(info.path.dropLast()))
            let step: any Step
            if container.type == "blockquote" {
                step = LiftStep(blockRange: info.start..<(info.start + info.node.nodeSize))
            } else if (container.type == "listItem" || container.type == "taskItem"), info.path.count >= 3 {
                let itemPath = Array(info.path.dropLast())
                let listPath = Array(itemPath.dropLast())
                let list = state.document.node(atPath: listPath)
                guard isListType(list.type), listType(list.type, acceptsItemType: container.type), (itemPath.last ?? 0) == 0 else { return false }
                step = LiftListItemStep(at: state.selection.head)
            } else {
                return false
            }
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
                origin: .local
            ))
            return true
        }
    }

    public static func sinkListItem() -> Command {
        Command { state in
            guard state.selection.isCollapsed,
                  let info = state.document.blockInfo(containing: state.selection.head),
                  state.selection.head == info.start + 1,
                  info.path.count >= 3 else {
                return false
            }
            let itemPath = Array(info.path.dropLast())
            let listPath = Array(itemPath.dropLast())
            let item = state.document.node(atPath: itemPath)
            let list = state.document.node(atPath: listPath)
            guard isListType(list.type), listType(list.type, acceptsItemType: item.type), (itemPath.last ?? 0) > 0 else {
                return false
            }
            let step = SinkListItemStep(at: state.selection.head)
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
                origin: .local
            ))
            return true
        }
    }

    public static func liftListItem() -> Command {
        Command { state in
            guard state.selection.isCollapsed,
                  let info = state.document.blockInfo(containing: state.selection.head),
                  state.selection.head == info.start + 1,
                  info.path.count >= 3 else {
                return false
            }
            let itemPath = Array(info.path.dropLast())
            let listPath = Array(itemPath.dropLast())
            let item = state.document.node(atPath: itemPath)
            let list = state.document.node(atPath: listPath)
            guard isListType(list.type), listType(list.type, acceptsItemType: item.type) else { return false }
            let step: any Step
            if info.path.count >= 5 {
                step = LiftNestedListItemStep(at: state.selection.head)
            } else {
                step = LiftListItemStep(at: state.selection.head)
            }
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
                origin: .local
            ))
            return true
        }
    }

    /// Wraps the block at the caret in a blockquote (the headless side of a
    /// blockquote toolbar button and of the `> ` input rule).
    public static func wrapInBlockquote() -> Command {
        Command { state in
            guard let info = state.document.blockInfo(containing: state.selection.head) else { return false }
            let step = WrapInStep(
                blockRange: info.start..<(info.start + info.node.nodeSize),
                containerType: "blockquote"
            )
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: step.map(state.selection.anchor), head: step.map(state.selection.head)),
                origin: .local
            ))
            return true
        }
    }

    /// Wraps the top-level textblock at the caret in a one-item list of
    /// `listType` (`bulletList`/`orderedList`/`taskList`) — the headless side of
    /// the list toolbar buttons and of the `- ` / `1. ` input rules. No-ops when
    /// the caret is not in a top-level textblock (wrapping a block already inside
    /// a list would nest it, which Tab handles instead).
    public static func wrapInList(_ listType: String) -> Command {
        Command { state in
            guard isListType(listType),
                  let info = state.document.blockInfo(containing: state.selection.head),
                  info.node.isTextblock,
                  info.path.count == 1 else {
                return false
            }
            let step = WrapInListStep(
                blockRange: info.start..<(info.start + info.node.nodeSize),
                listType: listType,
                listAttrs: listType == "orderedList" ? ["start": .int(1)] : [:],
                itemType: itemType(forListType: listType)
            )
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: step.map(state.selection.anchor), head: step.map(state.selection.head)),
                origin: .local
            ))
            return true
        }
    }

    /// A heading of any level toggles back to a paragraph; a paragraph becomes
    /// a heading of `level`.
    public static func toggleHeading(level: Int) -> Command {
        Command { state in
            let isHeading = state.document.blockInfo(containing: state.selection.head)?.node.type == "heading"
            return try setBlockType(headingLevel: isHeading ? nil : level).run(in: &state)
        }
    }

    /// Sets the block at the caret to a heading of `level`, or a paragraph when
    /// `level` is nil — non-toggling, for a heading dropdown.
    public static func setBlockType(headingLevel level: Int?) -> Command {
        Command { state in
            try dispatchCollapsing(SetBlockTypeStep(at: state.selection.head, headingLevel: level), in: &state)
            return true
        }
    }

    /// Sets the block's `textAlign` (the headless side of the alignment buttons,
    /// slice 13). `nil`/`"left"` clears it.
    public static func setTextAlign(_ value: String?) -> Command {
        Command { state in
            try dispatchCollapsing(SetTextAlignStep(at: state.selection.head, value: value), in: &state)
            return true
        }
    }

    public static func toggleTaskItemChecked() -> Command {
        Command { state in
            guard let info = state.document.blockInfo(containing: state.selection.head),
                  info.path.count >= 3 else {
                return false
            }
            let item = state.document.node(atPath: Array(info.path.dropLast()))
            guard item.type == "taskItem" else { return false }
            let next = !(item.attrs["checked"]?.boolValue ?? false)
            try dispatchCollapsing(SetTaskItemCheckedStep(at: state.selection.head, checked: next), in: &state)
            return true
        }
    }

    /// Wraps the (non-empty) selection in a link Mark. Used by the link popover
    /// (slice 08) and by pasting a URL onto a selection.
    public static func setLink(href: String) -> Command {
        Command { state in
            let lower = min(state.selection.anchor, state.selection.head)
            let upper = max(state.selection.anchor, state.selection.head)
            guard lower < upper else { return false }
            try state.dispatch(Transaction(
                steps: [AddMarkStep(from: lower, to: upper, mark: .link(href: href))],
                selection: state.selection,
                origin: .local
            ))
            return true
        }
    }

    public static func toggleMark(_ mark: Mark) -> Command {
        Command { state in
            let lower = min(state.selection.anchor, state.selection.head)
            let upper = max(state.selection.anchor, state.selection.head)
            guard lower < upper else {
                state.toggleTypingMark(mark)
                return true
            }

            let step: any Step = state.document.rangeHasMark(from: lower, to: upper, mark: mark)
                ? RemoveMarkStep(from: lower, to: upper, mark: mark)
                : AddMarkStep(from: lower, to: upper, mark: mark)
            try state.dispatch(Transaction(steps: [step], selection: state.selection, origin: .local))
            return true
        }
    }

    /// Dispatches a single block-attribute Step with the selection collapsed
    /// to the head — what the block-level toolbar actions do.
    private static func dispatchCollapsing(_ step: any Step, in state: inout EditorState) throws {
        let head = state.selection.head
        try state.dispatch(Transaction(
            steps: [step],
            selection: TextSelection(anchor: head, head: head),
            origin: .local
        ))
    }
}
