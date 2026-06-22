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

    /// Regression guard for the canonical reconnect path: a reconnect that
    /// introduces a *new* block, followed by a *deep* edit into that block, must
    /// converge on B. (The deep edit is one the fragment observer never sees, so
    /// it relies on the new block having been observed during the reconnect
    /// reconcile.)
    func testDeepEditIntoReconnectIntroducedBlockConverges() async throws {
        let coreA = makeCore("hello")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore("")
        let docB = YDoc()
        let bindingB = YBinding(core: coreB, doc: docB)
        let signal = AsyncStream<Bool>.makeStream()
        bindingB.attach(syncedSignal: signal.stream)

        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        signal.continuation.yield(true)
        await waitForDocumentText("hello", in: coreB)

        // A introduces a second block while B is offline.
        coreA.document = Document(.doc([.paragraph([.text("hello")]), .paragraph([.text("world")])]))
        appendCaret(coreA)
        try coreA.insertText("!") // forces the two-block tree to encode

        // B reconnects: the new "world" block arrives and must be observed.
        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        signal.continuation.yield(true)
        await waitForDocumentText("helloworld!", in: coreB)

        // A now deep-edits inside that block (a change the fragment observer never sees).
        appendCaret(coreA)
        try coreA.insertText("?")
        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        await waitForDocumentText("helloworld!?", in: coreB)

        XCTAssertEqual(coreB.document.plainText, coreA.document.plainText)
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
