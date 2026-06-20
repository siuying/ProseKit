import ProseModel

/// How a recorded edit groups with the one before it for undo. A run of
/// `.typing` (or `.deleting`) keystrokes that stays contiguous at the caret
/// collapses into a single undo step; `.none` always starts a fresh step.
public enum HistoryCoalescing: Sendable, Equatable {
    case none
    case typing
    case deleting
}

public struct EditorHistory: Sendable {
    var undoStack: [EditorHistoryEntry] = []
    var redoStack: [EditorHistoryEntry] = []
    private let limit: Int
    private var pendingCoalescing: HistoryCoalescing = .none
    private var coalesceCaret: Position?

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records an undoable edit, merging it into the previous entry when the
    /// edit continues an unbroken typing/deleting run at the same caret.
    mutating func record(
        _ entry: EditorHistoryEntry,
        coalescing: HistoryCoalescing,
        caretBefore: Position,
        caretAfter: Position
    ) {
        if coalescing != .none, coalescing == pendingCoalescing,
           coalesceCaret == caretBefore, let previous = undoStack.popLast() {
            // The combined inverse is this edit's inverse followed by the older
            // one's; the restored selection is the one from before the run.
            undoStack.append(EditorHistoryEntry(
                steps: entry.steps + previous.steps,
                selection: previous.selection
            ))
        } else {
            undoStack.append(entry)
            if undoStack.count > limit {
                undoStack.removeFirst(undoStack.count - limit)
            }
        }
        redoStack.removeAll()
        pendingCoalescing = coalescing
        coalesceCaret = caretAfter
    }

    /// A local edit whose inverse could not be computed is not undoable, but it
    /// must still invalidate the redo stack so a later redo cannot replay
    /// against a document that has since diverged.
    mutating func invalidateRedo() {
        redoStack.removeAll()
        breakCoalescing()
    }

    /// Ends the current typing/deleting run so the next edit starts a fresh
    /// undo step (e.g. after the caret moves or after an undo/redo).
    mutating func breakCoalescing() {
        pendingCoalescing = .none
        coalesceCaret = nil
    }

    mutating func popUndo() -> EditorHistoryEntry? {
        undoStack.popLast()
    }

    mutating func popRedo() -> EditorHistoryEntry? {
        redoStack.popLast()
    }

    mutating func pushUndo(_ entry: EditorHistoryEntry) {
        undoStack.append(entry)
    }

    mutating func pushRedo(_ entry: EditorHistoryEntry) {
        redoStack.append(entry)
    }
}

public struct EditorHistoryEntry: Sendable {
    var steps: [any Step]
    var selection: TextSelection

    init(steps: [any Step], selection: TextSelection) {
        self.steps = steps
        self.selection = selection
    }
}
