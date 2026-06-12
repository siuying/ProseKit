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

public enum Commands {
    public static func splitBlock() -> Command {
        Command { state in
            guard state.selection.isCollapsed else { return false }
            let (document, selection, changedRange) = try state.document.splitBlock(at: state.selection.head)
            state.replaceDocument(document, selection: selection, changedRange: changedRange)
            return true
        }
    }

    public static func joinBackward() -> Command {
        Command { state in
            guard state.selection.isCollapsed,
                  let result = try state.document.joinBackward(at: state.selection.head) else {
                return false
            }
            state.replaceDocument(result.0, selection: result.1, changedRange: result.2)
            return true
        }
    }

    public static func toggleHeading(level: Int) -> Command {
        Command { state in
            let (document, selection, changedRange) = try state.document.togglingHeading(
                at: state.selection.head,
                level: level
            )
            state.replaceDocument(document, selection: selection, changedRange: changedRange)
            return true
        }
    }

    /// Sets the block at the caret to a heading of `level`, or a paragraph when
    /// `level` is nil — non-toggling, for a heading dropdown.
    public static func setBlockType(headingLevel level: Int?) -> Command {
        Command { state in
            let (document, selection, changedRange) = try state.document.settingBlockType(
                at: state.selection.head,
                headingLevel: level
            )
            state.replaceDocument(document, selection: selection, changedRange: changedRange)
            return true
        }
    }

    /// Sets the block's `textAlign` (the headless side of the alignment buttons,
    /// slice 13). `nil`/`"left"` clears it.
    public static func setTextAlign(_ value: String?) -> Command {
        Command { state in
            let (document, selection, changedRange) = try state.document.settingTextAlign(
                at: state.selection.head,
                to: value
            )
            state.replaceDocument(document, selection: selection, changedRange: changedRange)
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
            let mark = Mark(type: "link", attrs: ["href": .string(href)])
            let document = try state.document.addingMark(from: lower, to: upper, mark: mark)
            state.replaceDocument(document, selection: state.selection, changedRange: lower..<upper)
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

            let document = state.document.rangeHasMark(from: lower, to: upper, mark: mark)
                ? try state.document.removingMark(from: lower, to: upper, mark: mark)
                : try state.document.addingMark(from: lower, to: upper, mark: mark)
            state.replaceDocument(document, selection: state.selection, changedRange: lower..<upper)
            return true
        }
    }
}
