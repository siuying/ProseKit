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
    public static func splitBlock() -> Command {
        Command { state in
            guard state.selection.isCollapsed else { return false }
            let step = SplitBlockStep(at: state.selection.head)
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
            guard state.selection.isCollapsed,
                  state.document.canJoinBackward(at: state.selection.head) else {
                return false
            }
            let step = JoinBlocksStep(at: state.selection.head)
            let caret = step.map(state.selection.head)
            try state.dispatch(Transaction(
                steps: [step],
                selection: TextSelection(anchor: caret, head: caret),
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
