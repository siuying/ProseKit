import Foundation
import ProseModel

public struct EditorState: Sendable {
    public private(set) var document: Document
    public private(set) var selection: TextSelection
    public private(set) var lastTransaction: AppliedTransaction?
    public private(set) var typingMarks: [Mark]
    public private(set) var history: EditorHistory

    public init(
        document: Document,
        selection: TextSelection? = nil,
        lastTransaction: AppliedTransaction? = nil,
        typingMarks: [Mark] = [],
        history: EditorHistory = EditorHistory()
    ) {
        self.document = document
        self.selection = selection ?? TextSelection(anchor: document.endTextPosition, head: document.endTextPosition)
        self.lastTransaction = lastTransaction
        self.typingMarks = typingMarks
        self.history = history
    }

    public mutating func insertText(_ text: String) throws {
        let from = min(selection.anchor, selection.head)
        let to = max(selection.anchor, selection.head)
        let head = from + text.count
        // Pending typing Marks ride on the Step itself; they only apply at a
        // collapsed caret (replacing a selection types plain).
        try dispatch(Transaction(
            steps: [ReplaceStep(from: from, to: to, insertText: text, insertMarks: from == to ? typingMarks : [])],
            selection: TextSelection(anchor: head, head: head),
            origin: .local
        ))
    }

    public mutating func deleteBackward() throws {
        if !selection.isCollapsed {
            try insertText("")
            return
        }
        // At a block's text start there is no character to the left inside
        // the block: joining with the previous block is a Command
        // (joinBackward) the view runs first, and at the document start
        // Backspace is inert. A designed no-op, not an error.
        guard let textStart = document.blockTextStart(at: selection.head),
              selection.head > textStart else { return }
        let head = selection.head - 1
        try dispatch(Transaction(
            steps: [ReplaceStep(from: head, to: selection.head, insertText: "")],
            selection: TextSelection(anchor: head, head: head),
            origin: .local
        ))
    }

    /// The only mutation path: every edit is a Transaction of Steps, so the
    /// Changed Range, Origin, and (future) history all flow from one seam.
    public mutating func dispatch(_ transaction: Transaction, recordsHistory: Bool = true) throws {
        let beforeDocument = document
        let beforeSelection = selection
        let undoSteps = try? Self.invertedSteps(for: transaction.steps, against: beforeDocument).reversed()
        let applied = try transaction.apply(to: document)
        document = applied.document
        selection = applied.selection
        lastTransaction = applied
        if let undoSteps, recordsHistory, transaction.origin == .local, !transaction.steps.isEmpty {
            history.recordUndo(EditorHistoryEntry(steps: Array(undoSteps), selection: beforeSelection))
        }
    }

    public mutating func undo() throws -> Bool {
        guard let entry = history.popUndo() else { return false }
        let redoSteps = try Self.invertedSteps(for: entry.steps, against: document).reversed()
        let selectionBeforeUndo = selection
        try dispatch(
            Transaction(steps: entry.steps, selection: entry.selection, origin: .history),
            recordsHistory: false
        )
        history.pushRedo(EditorHistoryEntry(steps: Array(redoSteps), selection: selectionBeforeUndo))
        return true
    }

    public mutating func redo() throws -> Bool {
        guard let entry = history.popRedo() else { return false }
        let undoSteps = try Self.invertedSteps(for: entry.steps, against: document).reversed()
        let selectionBeforeRedo = selection
        try dispatch(
            Transaction(steps: entry.steps, selection: entry.selection, origin: .history),
            recordsHistory: false
        )
        history.pushUndo(EditorHistoryEntry(steps: Array(undoSteps), selection: selectionBeforeRedo))
        return true
    }

    private static func invertedSteps(for steps: [any Step], against document: Document) throws -> [any Step] {
        var current = document
        var inversions: [any Step] = []
        for step in steps {
            inversions.append(try step.inverted(in: current))
            current = try step.apply(to: current).document
        }
        return inversions
    }

    // MARK: - Active state (toolbar queries)

    /// Whether `mark` is active at the Selection: the whole range carries it,
    /// or — at a collapsed caret — it is a pending typing Mark, else the Mark
    /// the character to the left carries (what the next typed text inherits).
    public func isActive(_ mark: Mark) -> Bool {
        let lower = min(selection.anchor, selection.head)
        let upper = max(selection.anchor, selection.head)
        if lower < upper {
            return document.rangeHasMark(from: lower, to: upper, mark: mark)
        }
        if !typingMarks.isEmpty {
            return typingMarks.contains(mark)
        }
        guard lower > 0, let info = document.blockInfo(containing: lower), lower > info.start + 1 else {
            return false
        }
        return document.rangeHasMark(from: lower - 1, to: lower, mark: mark)
    }

    /// The type of the Block Node containing the Selection head (e.g.
    /// `paragraph`, `heading`).
    public var activeBlockType: String {
        document.blockInfo(containing: selection.head)?.node.type ?? "paragraph"
    }

    /// The heading level at the Selection head, or nil when it is not a heading.
    public var activeHeadingLevel: Int? {
        let node = document.blockInfo(containing: selection.head)?.node
        guard node?.type == "heading" else { return nil }
        return node?.attrs["level"]?.intValue
    }

    public var activeListType: String? {
        Commands.activeListType(in: self)
    }

    public var canSinkListItem: Bool {
        Commands.canSinkListItem(in: self)
    }

    public var canLiftListItem: Bool {
        Commands.canLiftListItem(in: self)
    }

    public var canToggleTaskItemChecked: Bool {
        Commands.canToggleTaskItemChecked(in: self)
    }

    public var canSetLink: Bool {
        !selection.isCollapsed
    }

    public var hasHighlight: Bool {
        let lower = min(selection.anchor, selection.head)
        let upper = max(selection.anchor, selection.head)
        guard lower < upper else { return false }
        return document.marks(from: lower, to: upper).contains { $0.type == "highlight" }
    }

    public mutating func toggleTypingMark(_ mark: Mark) {
        if typingMarks.contains(mark) {
            typingMarks.removeAll { $0 == mark }
        } else {
            typingMarks = MarkRules.adding(mark, to: typingMarks)
        }
    }
}
