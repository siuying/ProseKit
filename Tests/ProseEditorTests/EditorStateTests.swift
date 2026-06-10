import XCTest
@testable import ProseEditor
@testable import ProseModel

final class EditorStateTests: XCTestCase {
    func testInsertAndDeleteDispatchLocalTransactions() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hi")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        try state.insertText("!")
        XCTAssertEqual(state.document.plainText, "hi!")
        XCTAssertEqual(state.selection, TextSelection(anchor: 5, head: 5))
        XCTAssertEqual(state.dispatchedTransactions.map(\.origin), [.local])

        try state.deleteBackward()
        XCTAssertEqual(state.document.plainText, "hi")
        XCTAssertEqual(state.selection, TextSelection(anchor: 4, head: 4))
        XCTAssertEqual(state.dispatchedTransactions.map(\.origin), [.local, .local])
    }

    func testIncrementalLayoutKeepsUnaffectedBoxesCached() throws {
        let document = Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([.text("world")]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 320)
        let initial = try store.layout(document)

        let step = ReplaceStep(from: 14, to: 14, insertText: "!")
        let applied = try step.apply(to: document)
        let updated = try store.layout(applied.document, changedRange: applied.changedRange)

        XCTAssertEqual(updated.children[0].typesetID, initial.children[0].typesetID)
        XCTAssertNotEqual(updated.children[1].typesetID, initial.children[1].typesetID)
    }
}
