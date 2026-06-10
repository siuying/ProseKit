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
            let (document, selection) = try state.document.splitBlock(at: state.selection.head)
            state.replaceDocument(document, selection: selection)
            return true
        }
    }

    public static func joinBackward() -> Command {
        Command { state in
            guard state.selection.isCollapsed,
                  let result = try state.document.joinBackward(at: state.selection.head) else {
                return false
            }
            state.replaceDocument(result.0, selection: result.1)
            return true
        }
    }

    public static func toggleHeading(level: Int) -> Command {
        Command { state in
            let (document, selection) = try state.document.togglingHeading(at: state.selection.head, level: level)
            state.replaceDocument(document, selection: selection)
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
            state.replaceDocument(document, selection: state.selection)
            return true
        }
    }
}
