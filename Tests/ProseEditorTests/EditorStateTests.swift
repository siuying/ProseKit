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
        XCTAssertEqual(state.lastTransaction?.origin, .local)
        XCTAssertEqual(state.lastTransaction?.changedRange, 4..<5)

        try state.deleteBackward()
        XCTAssertEqual(state.document.plainText, "hi")
        XCTAssertEqual(state.selection, TextSelection(anchor: 4, head: 4))
        XCTAssertEqual(state.lastTransaction?.origin, .local)
        XCTAssertEqual(state.lastTransaction?.changedRange, 4..<5)
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

        let (updatedDocument, _, changedRange) = try document.splitBlock(at: 4)
        let updated = try store.layout(updatedDocument, changedRange: changedRange)

        XCTAssertEqual(updated.children.count, 4)
        XCTAssertEqual(updated.children[3].node.plainText, "gamma")
        XCTAssertEqual(
            updated.children[3].typesetID,
            initial.children[2].typesetID,
            "blocks below the split should align with their old index and be reused"
        )
    }
}
