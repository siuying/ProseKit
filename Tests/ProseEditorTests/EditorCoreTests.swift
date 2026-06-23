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

    func testReplacingASelectionWithTriggerFiresRuleOnResult() throws {
        // ProseMirror parity: rules evaluate on the text before the caret after
        // insertion, so replacing a whole-block selection with a trigger still
        // completes the shortcut (this is also what makes replacement-range and
        // autocomplete input work).
        let core = EditorCore(document: Document(.doc([.paragraph([.text("abc")])])))
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        core.setSelection(TextSelection(anchor: start, head: start + 3))

        try core.insertText("# ")

        XCTAssertEqual(core.document.root.content[0].type, "heading")
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

    /// Types `text` one character at a time through the live seam, so each
    /// keystroke runs the input-rule pass exactly as the keyboard would.
    private func typeLive(_ text: String, into core: EditorCore) throws {
        for character in text { try core.insertText(String(character)) }
    }

    private func runs(_ core: EditorCore) -> [Node] {
        core.document.root.content[0].content
    }

    func testTypingStarItalicConvertsOnlyAfterClosingDelimiterLive() throws {
        let core = emptyParagraphCore()
        try typeLive("*Italic", into: core)
        XCTAssertEqual(core.document.root.content[0].plainText, "*Italic",
                       "no conversion until the closing delimiter is typed")

        try core.insertText("*")
        XCTAssertEqual(runs(core).map(\.text), ["Italic"])
        XCTAssertEqual(runs(core).map(\.marks), [[.italic]])
    }

    func testTypingBoldProducesBoldRunLive() throws {
        let core = emptyParagraphCore()
        try typeLive("**Bold**", into: core)
        XCTAssertEqual(runs(core).map(\.text), ["Bold"])
        XCTAssertEqual(runs(core).map(\.marks), [[.bold]])
    }

    func testTypingCodeLivePreservesPrecedingChar() throws {
        let core = emptyParagraphCore()
        try typeLive("a`Code`", into: core)
        XCTAssertEqual(runs(core).map(\.text), ["a", "Code"])
        XCTAssertEqual(runs(core).map(\.marks), [[], [.code]])
    }

    func testCharacterTypedAfterInlineShortcutIsPlain() throws {
        let core = emptyParagraphCore()
        try typeLive("*i*x", into: core)   // `*i*` italicises `i`, then `x` is typed
        XCTAssertEqual(runs(core).map(\.text), ["i", "x"])
        XCTAssertEqual(runs(core).map(\.marks), [[.italic], []])
    }

    func testCodeShortcutExcludesBoldViaMarkRules() throws {
        let core = emptyParagraphCore()
        XCTAssertTrue(core.run(Commands.toggleMark(.bold)))   // typing bold on
        // The whole token arrives as one committed run (one text node) so the
        // rule can match; char-by-char with an active toolbar Mark splits into
        // unmerged runs and hits the single-text-node limit (Phase 2 scope).
        try core.insertText("`code`")
        // The code rule's AddMarkStep adds code, and MarkRules drops the
        // excluded bold, so the run carries only code.
        XCTAssertEqual(runs(core).map(\.text), ["code"])
        XCTAssertEqual(runs(core).map(\.marks), [[.code]])
    }

    func testTypingAfterInlineShortcutWithTrailingSpaceIsPlain() throws {
        let core = emptyParagraphCore()
        try typeLive("*Italic* ", into: core)
        XCTAssertEqual(runs(core).map(\.text), ["Italic", " "])
        XCTAssertEqual(runs(core).map(\.marks), [[.italic], []])
    }

    func testToolbarMarkReadsInactiveRightAfterInlineShortcut() throws {
        let core = emptyParagraphCore()
        try core.insertText("*i*")   // italicises "i"; next char must be plain
        // Toolbar/active-state must agree with the plain-next-char behavior,
        // even though the caret sits to the right of an italic run.
        XCTAssertFalse(core.state.isActive(.italic))
    }

    // MARK: - Immediate Backspace revert (Phase 4)

    func testBackspaceAfterBlockRuleRestoresLiteralMarkdown() throws {
        let core = emptyParagraphCore()
        try core.insertText("# ")
        XCTAssertEqual(core.document.root.content[0].type, "heading")

        XCTAssertTrue(core.undoInputRule())
        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "# ")
    }

    func testBackspaceAfterInlineRuleRestoresLiteralMarkdown() throws {
        let core = emptyParagraphCore()
        try core.insertText("*Italic*")
        XCTAssertEqual(runs(core).map(\.marks), [[.italic]])

        XCTAssertTrue(core.undoInputRule())
        XCTAssertEqual(core.document.root.content[0].plainText, "*Italic*")
        XCTAssertEqual(runs(core).map(\.marks), [[]])
    }

    func testUndoInputRuleIsANoopAfterSelectionMove() throws {
        let core = emptyParagraphCore()
        try core.insertText("# ")
        core.setSelection(TextSelection(anchor: 1, head: 1))   // move the caret

        XCTAssertFalse(core.undoInputRule())
        XCTAssertEqual(core.document.root.content[0].type, "heading")
    }

    func testUndoInputRuleIsANoopAfterFurtherTyping() throws {
        let core = emptyParagraphCore()
        try core.insertText("# ")
        try core.insertText("x")   // an unrelated edit consumes the snapshot

        XCTAssertFalse(core.undoInputRule())
        XCTAssertEqual(core.document.root.content[0].type, "heading")
        XCTAssertEqual(core.document.root.content[0].plainText, "x")
    }

    func testUndoAfterBlockRevertDoesNotReapplyStaleConversion() throws {
        let core = emptyParagraphCore()
        try core.insertText("# ")
        XCTAssertTrue(core.undoInputRule())   // back to paragraph "# "

        // The conversion's undo entry must be dropped along with its document
        // change: Undo must never re-apply a stale heading inverse onto the
        // already-restored paragraph. (The first insert into an empty paragraph
        // is not itself recorded, so there is simply nothing left to undo.)
        XCTAssertFalse(core.undo())
        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "# ")
    }

    // MARK: - Composition / paste boundaries (Phase 5)

    func testInsertingWithoutInputRulesLeavesTriggerLiteral() throws {
        let core = emptyParagraphCore()
        try core.insertText("# ", applyingInputRules: false)
        XCTAssertEqual(core.document.root.content[0].type, "paragraph")
        XCTAssertEqual(core.document.root.content[0].plainText, "# ")
        // And no revert snapshot was armed, so Backspace deletes normally.
        XCTAssertFalse(core.undoInputRule())
    }

    func testReplacementThenCommittedTriggerStillFires() throws {
        // Simulates an autocomplete/replacement: text becomes "# " only after a
        // replacement lands, and the rule must still fire on the result.
        let core = EditorCore(document: Document(.doc([.paragraph([.text("#x")])])))
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        // Replace the "x" (the 2nd char) with a space, completing "# ".
        core.setSelection(TextSelection(anchor: start + 1, head: start + 2))
        try core.insertText(" ")
        XCTAssertEqual(core.document.root.content[0].type, "heading")
    }

    func testUndoAfterInlineRevertRevertsLiteralTypingAndKeepsPriorHistory() throws {
        // A non-empty starting block so the literal insertion is recorded.
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi ")])])))
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))

        try core.insertText("*x*")               // records the insert, then italicises
        XCTAssertTrue(core.undoInputRule())      // back to literal "hi *x*"
        XCTAssertEqual(core.document.root.content[0].plainText, "hi *x*")
        XCTAssertEqual(core.document.root.content[0].content.map(\.marks), [[]])

        // Prior history survives the revert: Undo removes the literal typing,
        // not a corrupted/duplicated conversion.
        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.root.content[0].plainText, "hi ")
    }
}
