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
        if !typingMarks.isEmpty, from == to {
            let updated = try document.replacingText(from: from, to: to, with: text, marks: typingMarks)
            replaceDocument(
                updated,
                selection: TextSelection(anchor: head, head: head),
                changedRange: from..<max(from + text.count, from + 1)
            )
            return
        }
        try dispatch(Transaction(
            steps: [ReplaceStep(from: from, to: to, insertText: text)],
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

    public mutating func dispatch(_ transaction: Transaction) throws {
        let applied = try transaction.apply(to: document)
        document = applied.document
        selection = applied.selection
        lastTransaction = applied
    }

    public mutating func replaceDocument(
        _ document: Document,
        selection: TextSelection,
        origin: Origin = .local,
        changedRange: Range<Position>
    ) {
        self.document = document
        self.selection = selection
        lastTransaction = AppliedTransaction(
            document: document,
            selection: selection,
            origin: origin,
            changedRange: changedRange
        )
    }

    public mutating func toggleTypingMark(_ mark: Mark) {
        if typingMarks.contains(mark) {
            typingMarks.removeAll { $0 == mark }
        } else {
            typingMarks.append(mark)
        }
    }
}
