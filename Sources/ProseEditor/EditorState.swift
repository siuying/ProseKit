import Foundation
import ProseModel

public struct EditorState: Sendable {
    public private(set) var document: Document
    public private(set) var selection: TextSelection
    public private(set) var lastTransaction: AppliedTransaction?
    public private(set) var typingMarks: [Mark]

    public init(
        document: Document,
        selection: TextSelection? = nil,
        lastTransaction: AppliedTransaction? = nil,
        typingMarks: [Mark] = []
    ) {
        self.document = document
        self.selection = selection ?? TextSelection(anchor: document.endTextPosition, head: document.endTextPosition)
        self.lastTransaction = lastTransaction
        self.typingMarks = typingMarks
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
        guard selection.head > 0 else { return }
        let head = selection.head - 1
        try dispatch(Transaction(
            steps: [ReplaceStep(from: head, to: selection.head, insertText: "")],
            selection: TextSelection(anchor: head, head: head),
            origin: .local
        ))
    }

    /// The only mutation path: every edit is a Transaction of Steps, so the
    /// Changed Range, Origin, and (future) history all flow from one seam.
    public mutating func dispatch(_ transaction: Transaction) throws {
        let applied = try transaction.apply(to: document)
        document = applied.document
        selection = applied.selection
        lastTransaction = applied
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

    public mutating func toggleTypingMark(_ mark: Mark) {
        if typingMarks.contains(mark) {
            typingMarks.removeAll { $0 == mark }
        } else {
            typingMarks = MarkRules.adding(mark, to: typingMarks)
        }
    }
}
