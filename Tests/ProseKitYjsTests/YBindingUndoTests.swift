import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingUndoTests: XCTestCase {
    private func makeCore(_ text: String) -> EditorCore {
        let core = EditorCore(document: Document(.doc([.paragraph(text.isEmpty ? [] : [.text(text)])])))
        appendCaret(core)
        return core
    }

    private func appendCaret(_ core: EditorCore) {
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))
    }

    private func textStart(_ core: EditorCore) -> Position {
        core.document.endTextPosition - core.document.totalTextCount
    }

    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    private func waitForText(_ expected: String, in core: EditorCore) async {
        for _ in 0..<20 where core.document.plainText != expected { await Task.yield() }
    }

    // MARK: - Undo / redo

    func testCollaborativeUndoRevertsLocalEdit() async throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        appendCaret(core)
        try core.insertText("!")
        XCTAssertEqual(core.document.plainText, "hi!")
        XCTAssertTrue(core.canUndo)

        XCTAssertTrue(core.undo())
        await waitForText("hi", in: core)

        XCTAssertEqual(core.document.plainText, "hi")
        XCTAssertFalse(core.canUndo)
        XCTAssertTrue(core.canRedo)
        withExtendedLifetime(binding) {}
    }

    func testRedoRestoresUndoneEdit() async throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        appendCaret(core)
        try core.insertText("!")
        XCTAssertTrue(core.undo())
        await waitForText("hi", in: core)

        XCTAssertTrue(core.redo())
        await waitForText("hi!", in: core)
        XCTAssertEqual(core.document.plainText, "hi!")
        withExtendedLifetime(binding) {}
    }

    func testTypingBurstUndoesAsOneUnit() async throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        // A burst of typing with no caret jump coalesces into one undo unit.
        appendCaret(core)
        try core.insertText("a")
        try core.insertText("b")
        try core.insertText("c")
        XCTAssertEqual(core.document.plainText, "hiabc")

        XCTAssertTrue(core.undo())
        await waitForText("hi", in: core)
        XCTAssertEqual(core.document.plainText, "hi") // whole burst reverted at once
        withExtendedLifetime(binding) {}
    }

    func testCaretJumpSplitsUndoUnits() async throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        appendCaret(core)
        try core.insertText("a")
        appendCaret(core) // a caret move breaks coalescing -> stopCapturing
        try core.insertText("b")
        XCTAssertEqual(core.document.plainText, "hiab")

        XCTAssertTrue(core.undo())
        await waitForText("hia", in: core) // only the second edit reverts
        XCTAssertTrue(core.undo())
        await waitForText("hi", in: core)
        withExtendedLifetime(binding) {}
    }

    // MARK: - Concurrency

    func testConcurrentRemoteEditSurvivesUndo() async throws {
        let coreA = makeCore("hi")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore("")
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()
        XCTAssertEqual(coreB.document.plainText, "hi")

        // A appends "!"; B concurrently prepends "X".
        appendCaret(coreA)
        try coreA.insertText("!")
        let bStart = textStart(coreB)
        coreB.setSelection(TextSelection(anchor: bStart, head: bStart))
        try coreB.insertText("X")

        try sync(docA, docB)
        for _ in 0..<20 where coreA.document.plainText != coreB.document.plainText { await Task.yield() }
        XCTAssertEqual(coreA.document.plainText, "Xhi!")

        // A undoes — only A's "!" reverts; B's "X" survives.
        XCTAssertTrue(coreA.undo())
        await waitForText("Xhi", in: coreA)
        try sync(docA, docB)
        await waitForText("Xhi", in: coreB)

        XCTAssertEqual(coreA.document.plainText, "Xhi")
        XCTAssertEqual(coreB.document.plainText, "Xhi")
        withExtendedLifetime((bindingA, bindingB)) {}
    }

    // MARK: - Solo mode is unchanged

    func testSoloUndoUnchangedWithoutBinding() throws {
        let core = makeCore("hi")
        appendCaret(core)
        try core.insertText("!")

        XCTAssertTrue(core.canUndo)
        XCTAssertTrue(core.undo()) // synchronous step-based undo, no binding
        XCTAssertEqual(core.document.plainText, "hi")
    }

    func testDetachLeavesNoStaleSoloHistory() throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        appendCaret(core)
        try core.insertText("!") // a collaborative local edit

        binding.detach()

        // The collaborative edit was never recorded into the solo history (its
        // positions could be invalidated by concurrent remote ops), so detach
        // exposes no stale, replay-unsafe undo step.
        XCTAssertFalse(core.canUndo)
        XCTAssertFalse(core.undo())
        XCTAssertEqual(core.document.plainText, "hi!")

        // Solo editing resumes cleanly: a fresh post-detach edit is undoable.
        appendCaret(core)
        try core.insertText("?")
        XCTAssertTrue(core.canUndo)
        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "hi!")
    }
}
