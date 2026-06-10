import Foundation
import ProseModel

public struct EditorState: Sendable {
    public private(set) var document: Document
    public private(set) var selection: TextSelection
    public private(set) var dispatchedTransactions: [AppliedTransaction]

    public init(
        document: Document,
        selection: TextSelection? = nil,
        dispatchedTransactions: [AppliedTransaction] = []
    ) {
        self.document = document
        self.selection = selection ?? TextSelection(anchor: document.endTextPosition, head: document.endTextPosition)
        self.dispatchedTransactions = dispatchedTransactions
    }

    public mutating func insertText(_ text: String) throws {
        let from = min(selection.anchor, selection.head)
        let to = max(selection.anchor, selection.head)
        let head = from + text.count
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
        dispatchedTransactions.append(applied)
    }

    public mutating func replaceDocument(_ document: Document, selection: TextSelection, origin: Origin = .local) {
        self.document = document
        self.selection = selection
        dispatchedTransactions.append(AppliedTransaction(document: document, selection: selection, origin: origin))
    }
}
