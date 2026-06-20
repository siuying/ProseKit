import XCTest
@testable import ProseEditor
@testable import ProseModel

@MainActor
final class EditorCoreTests: XCTestCase {
    func testCoreRelayoutsAfterDispatchingACommandAndAnswersGeometry() throws {
        let document = Document(.doc([
            .paragraph([.text("hello world")]),
        ]))
        let core = EditorCore(document: document, schema: .slice1)

        core.relayout(width: 320)
        let before = try XCTUnwrap(core.layoutBox)
        XCTAssertGreaterThan(before.frame.height, 0)

        core.setSelection(TextSelection(anchor: 2, head: 7))
        XCTAssertTrue(core.run(Commands.toggleMark(.bold)))

        XCTAssertEqual(core.document.root.content[0].content[0].marks, [.bold])
        XCTAssertEqual(core.selection, TextSelection(anchor: 2, head: 7))
        XCTAssertNotNil(core.lastTransaction?.changedRange)
        let after = try XCTUnwrap(core.layoutBox)
        XCTAssertEqual(after.frame.width, 320)
        XCTAssertGreaterThan(core.caretRect(for: core.selection.head).height, 0)
    }

    func testCoreExposesSharedEditorKeyBindings() throws {
        let bindings = EditorCore.sharedKeyBindings

        XCTAssertEqual(bindings.map(\.key), [.character("b"), .character("i"), .tab, .tab])
        XCTAssertEqual(bindings.map(\.modifiers), [.command, .command, [], .shift])
        XCTAssertEqual(bindings.map(\.action), [.toggleBold, .toggleItalic, .sinkListItem, .liftListItem])

        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let core = EditorCore(document: document)
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        core.setSelection(TextSelection(anchor: start, head: start + 5))

        XCTAssertTrue(core.runKeyBindingAction(.toggleBold))
        XCTAssertEqual(core.document.root.content[0].content[0].marks, [.bold])
    }

    func testConsecutiveTypingCollapsesIntoOneUndoStep() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi")])])))
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))

        try core.insertText("a")
        try core.insertText("b")
        try core.insertText("c")
        XCTAssertEqual(core.document.plainText, "hiabc")

        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "hi")
        XCTAssertFalse(core.canUndo)

        XCTAssertTrue(core.redo())
        XCTAssertEqual(core.document.plainText, "hiabc")
        XCTAssertFalse(core.canRedo)
    }

    func testCaretMovementStartsANewUndoStep() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("")])])))
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        core.setSelection(TextSelection(anchor: start, head: start))

        try core.insertText("a")
        try core.insertText("b")
        let mid = start + 1
        core.setSelection(TextSelection(anchor: mid, head: mid))
        try core.insertText("X")
        XCTAssertEqual(core.document.plainText, "aXb")

        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "ab")
        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "")
    }

    func testConsecutiveBackspacesCollapseIntoOneUndoStep() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("abc")])])))
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))

        try core.deleteBackward()
        try core.deleteBackward()
        XCTAssertEqual(core.document.plainText, "a")

        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "abc")
    }
}
