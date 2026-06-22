import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingReconnectTests: XCTestCase {
    private func makeCore(_ text: String) -> EditorCore {
        let core = EditorCore(document: Document(.doc([.paragraph(text.isEmpty ? [] : [.text(text)])])))
        core.setSelection(TextSelection(anchor: core.document.endTextPosition, head: core.document.endTextPosition))
        return core
    }

    private func appendCaret(_ core: EditorCore) {
        let end = core.document.endTextPosition
        core.setSelection(TextSelection(anchor: end, head: end))
    }

    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    private func waitForDocumentText(_ expected: String, in core: EditorCore) async {
        for _ in 0..<10 where core.document.plainText != expected { await Task.yield() }
    }

    // MARK: - Collaborative-undo guard (ADR 0010)

    func testUndoSuppressedWhileBound() throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        try core.insertText("!") // a normally-undoable local edit

        XCTAssertFalse(core.canUndo)
        XCTAssertFalse(core.canRedo)
        XCTAssertFalse(core.undo()) // gesture is a no-op
        XCTAssertEqual(core.document.plainText, "hi!") // undo did nothing
        withExtendedLifetime(binding) {}
    }

    func testUndoRestoredAfterDetach() throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        try core.insertText("!")
        XCTAssertFalse(core.canUndo)

        binding.detach()

        XCTAssertTrue(core.canUndo) // solo step history restored
        XCTAssertTrue(core.undo())
        XCTAssertEqual(core.document.plainText, "hi")
    }

    // MARK: - Reconnect / offline convergence

    func testPartitionedPeersConvergeOnHeal() async throws {
        let coreA = makeCore("hello")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore("")
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()
        XCTAssertEqual(coreB.document.plainText, "hello")

        // Partition: both edit with no sync in between.
        appendCaret(coreA)
        try coreA.insertText(" A")
        appendCaret(coreB)
        try coreB.insertText(" B")

        // Heal.
        try sync(docA, docB)
        for _ in 0..<10 where coreA.document.plainText != coreB.document.plainText { await Task.yield() }

        XCTAssertEqual(coreA.document.plainText, coreB.document.plainText)
        XCTAssertTrue(coreA.document.plainText.contains("A"))
        XCTAssertTrue(coreA.document.plainText.contains("B"))
        withExtendedLifetime((bindingA, bindingB)) {}
    }

    func testReconnectReReconcilesViaSyncedSignal() async throws {
        let coreA = makeCore("hello")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore("")
        let docB = YDoc()
        let bindingB = YBinding(core: coreB, doc: docB)
        let signal = AsyncStream<Bool>.makeStream()
        bindingB.attach(syncedSignal: signal.stream)

        // First sync completes → Join.
        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        signal.continuation.yield(true)
        await waitForDocumentText("hello", in: coreB)

        // A edits while B is "offline" (its updates are not delivered yet).
        appendCaret(coreA)
        try coreA.insertText(" more")

        // B reconnects: its provider delivers the buffered update, then sync completes.
        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        signal.continuation.yield(true)
        await waitForDocumentText("hello more", in: coreB)

        XCTAssertEqual(coreB.document.plainText, "hello more")
        withExtendedLifetime(bindingA) {}
    }
}
