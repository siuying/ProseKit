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

    // MARK: - Live block input rules (Phase 1)

    func testTypingHashSpaceConvertsParagraphToHeadingLive() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let start = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: start, head: start))

        try core.insertText("# ")

        XCTAssertEqual(core.document.root.content[0].type, "heading")
        XCTAssertEqual(core.document.root.content[0].attrs["level"], .int(1))
        XCTAssertEqual(core.document.root.content[0].plainText, "")
    }

    func testTypingGtSpaceWrapsParagraphInBlockquoteLive() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let start = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: start, head: start))

        try core.insertText("> ")

        XCTAssertEqual(core.document.root.content[0].type, "blockquote")
    }

    func testInputRulesCanBeDisabled() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        core.inputRulesEnabled = false
        let start = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: start, head: start))

        try core.insertText("# ")

        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "# ")
    }

    func testReplacingASelectionWithTriggerDoesNotFireRule() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("abc")])])))
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        // Select the whole word, then "type" a trigger over it.
        core.setSelection(TextSelection(anchor: start, head: start + 3))

        try core.insertText("# ")

        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "# ")
    }

    func testTypingHashSpaceNotAtBlockStartStaysPlain() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("a")])])))
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))

        try core.insertText("# ")

        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "a# ")
    }

    // MARK: - Live inline mark rules (Phase 3)

    private func emptyParagraphCore() -> EditorCore {
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let start = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: start, head: start))
        return core
    }

    func testTypingStarItalicProducesItalicRunLive() throws {
        let core = emptyParagraphCore()
        try core.insertText("*Italic*")
        XCTAssertEqual(core.document.root.content[0].plainText, "Italic")
        XCTAssertEqual(core.document.root.content[0].content.first?.marks, [.italic])
    }

    func testTypingBoldProducesBoldRunLive() throws {
        let core = emptyParagraphCore()
        try core.insertText("**Bold**")
        XCTAssertEqual(core.document.root.content[0].plainText, "Bold")
        XCTAssertEqual(core.document.root.content[0].content.first?.marks, [.bold])
    }

    func testTypingCodeLivePreservesPrecedingChar() throws {
        let core = emptyParagraphCore()
        try core.insertText("a`Code`")
        XCTAssertEqual(core.document.root.content[0].plainText, "aCode")
        let runs = core.document.root.content[0].content
        XCTAssertEqual(runs.first?.marks, [])
        XCTAssertEqual(runs.last?.marks, [.code])
    }

    func testCharacterTypedAfterInlineShortcutIsPlain() throws {
        let core = emptyParagraphCore()
        try core.insertText("*i*")   // becomes italic "i"
        try core.insertText("x")     // the shortcut must not keep italic active
        XCTAssertEqual(core.document.root.content[0].plainText, "ix")
        let xRun = core.document.root.content[0].content.first { $0.text == "x" }
        XCTAssertEqual(xRun?.marks ?? [], [])
    }

    func testCodeShortcutExcludesBoldViaMarkRules() throws {
        let core = emptyParagraphCore()
        XCTAssertTrue(core.run(Commands.toggleMark(.bold)))   // typing bold on
        try core.insertText("`code`")
        XCTAssertEqual(core.document.root.content[0].plainText, "code")
        // Code excludes bold (MarkRules), so the run carries only code.
        XCTAssertEqual(core.document.root.content[0].content.first?.marks, [.code])
    }
}
