import ProseModel

public struct EditorHistory: Sendable {
    var undoStack: [EditorHistoryEntry] = []
    var redoStack: [EditorHistoryEntry] = []
    private let limit: Int

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    mutating func recordUndo(_ entry: EditorHistoryEntry) {
        undoStack.append(entry)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
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
