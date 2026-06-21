import XCTest
@testable import ProseEditor
@testable import ProseModel

/// The Yjs-agnostic collaboration seam on `EditorCore`: an outbound
/// `didApplyTransaction` that fires exactly once per applied Transaction across
/// every dispatch path, and an inbound `applyRemote` that applies a
/// remote-origin Transaction without touching local history.
@MainActor
final class EditorCoreSeamTests: XCTestCase {
    private func makeCore() -> EditorCore {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi")])])))
        core.setSelection(TextSelection(anchor: 4, head: 4))
        return core
    }

    func testDidApplyFiresOnceForLocalInsert() throws {
        let core = makeCore()
        var applied: [AppliedTransaction] = []
        core.didApplyTransaction = { applied.append($0) }

        try core.insertText("!")

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.origin, .local)
        XCTAssertEqual(core.document.plainText, "hi!")
    }

    func testDidApplyFiresOnceForDeleteBackward() throws {
        let core = makeCore()
        var count = 0
        core.didApplyTransaction = { _ in count += 1 }

        try core.deleteBackward()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(core.document.plainText, "h")
    }

    func testDidApplyDoesNotFireForNoOpDeleteBackward() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi")])])))
        core.setSelection(TextSelection(anchor: 2, head: 2)) // very start of text
        var count = 0
        core.didApplyTransaction = { _ in count += 1 }

        try core.deleteBackward() // inert at the document start

        XCTAssertEqual(count, 0)
    }

    func testDidApplyFiresOnceForCommand() {
        let core = makeCore()
        var applied: [AppliedTransaction] = []
        core.didApplyTransaction = { applied.append($0) }

        XCTAssertTrue(core.run(Commands.toggleHeading(level: 2)))

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.origin, .local)
        XCTAssertEqual(core.state.activeBlockType, "heading")
    }

    func testDidApplyDoesNotDoubleFireWhenRunDelegatesToDispatch() {
        // run() forwards to dispatch(); only one notification must surface.
        let core = makeCore()
        var count = 0
        core.didApplyTransaction = { _ in count += 1 }

        _ = core.run(Commands.toggleHeading(level: 2))

        XCTAssertEqual(count, 1)
    }

    func testDidApplyFiresOnceForUndoAndRedo() throws {
        let core = makeCore()
        try core.insertText("!")
        var applied: [AppliedTransaction] = []
        core.didApplyTransaction = { applied.append($0) }

        XCTAssertTrue(core.undo())
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.last?.origin, .history)
        XCTAssertEqual(core.document.plainText, "hi")

        XCTAssertTrue(core.redo())
        XCTAssertEqual(applied.count, 2)
        XCTAssertEqual(applied.last?.origin, .history)
        XCTAssertEqual(core.document.plainText, "hi!")
    }

    func testDidApplyDoesNotFireForNoOpUndo() {
        let core = makeCore() // nothing recorded yet
        var count = 0
        core.didApplyTransaction = { _ in count += 1 }

        XCTAssertFalse(core.undo())
        XCTAssertEqual(count, 0)
    }

    func testApplyRemoteSetsRemoteOriginAndRecordsNoHistory() {
        let core = makeCore()
        // A pre-existing local edit gives us an undo stack to prove the remote
        // apply leaves it untouched.
        try? core.insertText("!")
        XCTAssertTrue(core.canUndo)
        let canUndoBefore = core.canUndo
        let canRedoBefore = core.canRedo

        var applied: [AppliedTransaction] = []
        core.didApplyTransaction = { applied.append($0) }

        let head = core.document.endTextPosition
        let remote = Transaction(
            steps: [ReplaceStep(from: head, to: head, insertText: "?")],
            selection: TextSelection(anchor: head + 1, head: head + 1),
            origin: .remote
        )
        core.applyRemote(remote)

        XCTAssertEqual(core.document.plainText, "hi!?")
        XCTAssertEqual(core.lastTransaction?.origin, .remote)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.origin, .remote)
        // No history entry recorded for a remote apply.
        XCTAssertEqual(core.canUndo, canUndoBefore)
        XCTAssertEqual(core.canRedo, canRedoBefore)
    }

    func testApplyRemoteRelayoutsChangedRange() {
        let core = makeCore()
        core.relayout(width: 320)
        XCTAssertNotNil(core.layoutBox)

        let head = core.document.endTextPosition
        let remote = Transaction(
            steps: [ReplaceStep(from: head, to: head, insertText: " there")],
            selection: TextSelection(anchor: head + 6, head: head + 6),
            origin: .remote
        )
        core.applyRemote(remote)

        XCTAssertEqual(core.document.plainText, "hi there")
        XCTAssertNotNil(core.layoutBox, "a remote apply relayouts the changed range")
    }
}
