import XCTest
@testable import ProseEditor
@testable import ProseModel

final class EditorStateTests: XCTestCase {
    func testIsActiveReflectsSelectionMarks() throws {
        let document = Document(.doc([.paragraph([.text("hello", marks: [.bold]), .text(" world")])]))
        // Whole selection over the bold run.
        var state = EditorState(document: document, selection: TextSelection(anchor: 2, head: 7))
        XCTAssertTrue(state.isActive(.bold))
        XCTAssertFalse(state.isActive(.italic))

        // Selection spanning bold + plain is not fully bold.
        state = EditorState(document: document, selection: TextSelection(anchor: 2, head: 13))
        XCTAssertFalse(state.isActive(.bold))
    }

    func testIsActiveAtCollapsedCaretUsesLeftCharThenTypingMark() throws {
        // A caret inside a bold run inherits bold from the character to its left.
        let bold = Document(.doc([.paragraph([.text("hello", marks: [.bold])])]))
        let inBold = EditorState(document: bold, selection: TextSelection(anchor: 4, head: 4))
        XCTAssertTrue(inBold.isActive(.bold))

        // In plain text, a pending typing mark drives the active state.
        var inPlain = EditorState(
            document: Document(.doc([.paragraph([.text("hello")])])),
            selection: TextSelection(anchor: 4, head: 4)
        )
        XCTAssertFalse(inPlain.isActive(.bold))
        inPlain.toggleTypingMark(.bold)
        XCTAssertTrue(inPlain.isActive(.bold), "a pending typing mark is active")
    }

    func testActiveBlockTypeAndHeadingLevel() {
        let document = Document(.doc([
            .paragraph([.text("p")]),
            .heading(level: 3, [.text("h")]),
        ]))
        let inParagraph = EditorState(document: document, selection: TextSelection(anchor: 2, head: 2))
        XCTAssertEqual(inParagraph.activeBlockType, "paragraph")
        XCTAssertNil(inParagraph.activeHeadingLevel)

        let inHeading = EditorState(document: document, selection: TextSelection(anchor: 6, head: 6))
        XCTAssertEqual(inHeading.activeBlockType, "heading")
        XCTAssertEqual(inHeading.activeHeadingLevel, 3)
    }

    func testInsertAndDeleteDispatchLocalTransactions() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hi")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        try state.insertText("!")
        XCTAssertEqual(state.document.plainText, "hi!")
        XCTAssertEqual(state.selection, TextSelection(anchor: 5, head: 5))
        XCTAssertEqual(state.lastTransaction?.origin, .local)
        XCTAssertEqual(state.lastTransaction?.changedRange, 4..<5)

        try state.deleteBackward()
        XCTAssertEqual(state.document.plainText, "hi")
        XCTAssertEqual(state.selection, TextSelection(anchor: 4, head: 4))
        XCTAssertEqual(state.lastTransaction?.origin, .local)
        XCTAssertEqual(state.lastTransaction?.changedRange, 4..<5)
    }

    func testDeleteBackwardAtDocumentStartIsANoOp() throws {
        let document = Document(.doc([.paragraph([.text("hi")])]))
        var state = EditorState(
            document: document,
            selection: TextSelection(anchor: document.startTextPosition, head: document.startTextPosition)
        )

        // Backspace at the very start of the document must be inert, never
        // a thrown boundary error (it crashed debug builds as an assertion).
        XCTAssertNoThrow(try state.deleteBackward())
        XCTAssertEqual(state.document, document)
        XCTAssertEqual(state.selection, TextSelection(anchor: 2, head: 2))
    }

    func testDeleteBackwardAtBlockTextStartIsANoOpWithoutJoinCommand() throws {
        // The view runs joinBackward first; headless deleteBackward at a
        // block's text start must no-op rather than throw.
        let document = Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ]))
        var state = EditorState(document: document, selection: TextSelection(anchor: 9, head: 9))

        XCTAssertNoThrow(try state.deleteBackward())
        XCTAssertEqual(state.document, document)
    }

    func testTypingMarksInsertSuppliesChangedRange() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hi")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        state.toggleTypingMark(.code)
        try state.insertText("!")

        XCTAssertEqual(state.document.plainText, "hi!")
        XCTAssertEqual(state.lastTransaction?.changedRange, 4..<5)
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

    func testReusedBoxFragmentsTrackPositionAndYShifts() throws {
        let document = Document(.doc([
            .paragraph([.text("alpha")]),
            .paragraph([.text("beta")]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 120)
        let initial = try store.layout(document)

        // Grow the first paragraph so it wraps and pushes the second one down.
        let inserted = "a much longer opening sentence "
        let step = ReplaceStep(from: 2, to: 2, insertText: inserted)
        let applied = try step.apply(to: document)
        let updated = try store.layout(applied.document, changedRange: applied.changedRange)

        XCTAssertEqual(updated.children[1].typesetID, initial.children[1].typesetID, "unchanged block should be reused")
        XCTAssertGreaterThan(updated.children[1].frame.minY, initial.children[1].frame.minY)

        let fragment = updated.children[1].lineFragments[0]
        XCTAssertEqual(fragment.frame.minY, 0)
        let expectedStart = updated.children[1].positionRange.lowerBound + fragment.positionRange.lowerBound

        let mapper = GeometryMapper()
        let rect = mapper.caretRect(for: expectedStart + 2, in: updated)
        XCTAssertEqual(mapper.closestPosition(to: CGPoint(x: rect.midX, y: rect.midY), in: updated), expectedStart + 2)
    }

    func testIncrementalLayoutRealignsTailAfterBlockSplit() throws {
        let document = Document(.doc([
            .paragraph([.text("alpha")]),
            .paragraph([.text("beta")]),
            .paragraph([.text("gamma")]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 240)
        let initial = try store.layout(document)

        let split = try document.splitBlock(at: 4)
        let updated = try store.layout(split.document, changedRange: split.changedRange)

        XCTAssertEqual(updated.children.count, 4)
        XCTAssertEqual(updated.children[3].node.plainText, "gamma")
        XCTAssertEqual(
            updated.children[3].typesetID,
            initial.children[2].typesetID,
            "blocks below the split should align with their old index and be reused"
        )
    }
}
