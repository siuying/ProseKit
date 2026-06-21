import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingMarksTests: XCTestCase {
    // MARK: - Helpers

    private func makeCore(_ block: Node) -> EditorCore {
        let core = EditorCore(document: Document(.doc([block])))
        core.setSelection(TextSelection(anchor: 1, head: 1))
        return core
    }

    private func fragment(_ doc: YDoc) throws -> YXmlFragment {
        try doc.xmlFragment(named: YBinding.defaultFragmentName)
    }

    /// Seeds a replica's single paragraph with marked runs directly (no binding,
    /// so no echo), via the YXmlText delta API.
    private func seedMarkedReplica(_ doc: YDoc, _ runs: [MarkedRun]) throws {
        let fragment = try fragment(doc)
        let marked = MarkedText(runs: runs)
        try doc.write(origin: "seed") { transaction in
            let paragraph = try transaction.insertElement(named: "paragraph", into: fragment, at: 0)
            let textNode = try transaction.insertText(into: paragraph, at: 0)
            try transaction.applyDeltaJSON(marked.deltaJSON(), to: textNode)
        }
    }

    /// A remote-origin formatting change over the paragraph's existing text.
    private func remoteFormat(_ doc: YDoc, marks: [Mark], from: UInt32, length: UInt32) throws {
        let fragment = try fragment(doc)
        try doc.write(origin: "remote-peer") { transaction in
            let textNode = try XCTUnwrap(Self.textNode(in: fragment, transaction: transaction))
            let attributes = try JSONSerialization.data(withJSONObject: MarkedText.attributesObject(for: marks))
            try transaction.format(textNode, at: from, length: length, attributesJSON: attributes)
        }
    }

    private func replicaRuns(_ doc: YDoc) throws -> [MarkedRun] {
        let fragment = try fragment(doc)
        let data = try doc.read { transaction -> Data in
            guard let textNode = try Self.textNode(in: fragment, transaction: transaction) else { return Data() }
            return try transaction.deltaJSON(from: textNode)
        }
        return MarkedText(deltaJSON: data).runs
    }

    private func paragraphChildCount(_ doc: YDoc) throws -> Int {
        let fragment = try fragment(doc)
        return try doc.read { transaction in
            guard case let .element(paragraph) = try transaction.child(at: 0, in: fragment) else { return 0 }
            return Int(try transaction.childCount(of: paragraph))
        }
    }

    private func documentRuns(_ core: EditorCore) -> [MarkedRun] {
        guard let block = core.document.root.content.first else { return [] }
        return MarkedText(textblock: block).runs
    }

    private static func textNode(in fragment: YXmlFragment, transaction: YReadTransaction) throws -> YXmlText? {
        guard try transaction.childCount(of: fragment) > 0,
              case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
              try transaction.childCount(of: paragraph) > 0,
              case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
        else { return nil }
        return textNode
    }

    /// Marks within a run carry no canonical order; sort them for comparison.
    private func canonical(_ runs: [MarkedRun]) -> [MarkedRun] {
        runs.map { MarkedRun(text: $0.text, marks: $0.marks.sorted { $0.type < $1.type }) }
    }

    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    // MARK: - Encode (PM → Y)

    func testJoinEncodesMarksToReplica() throws {
        let core = makeCore(.paragraph([.text("ab", marks: [.bold]), .text("cd")]))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(
            canonical(try replicaRuns(doc)),
            canonical([MarkedRun(text: "ab", marks: [.bold]), MarkedRun(text: "cd", marks: [])])
        )
    }

    func testMixedMarkRunIsOneYXmlText() throws {
        let core = makeCore(.paragraph([.text("ab", marks: [.bold]), .text("cd")]))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        // A run of differently-marked spans coalesces into a single YXmlText.
        XCTAssertEqual(try paragraphChildCount(doc), 1)
        withExtendedLifetime(binding) {}
    }

    func testLinkMarkAttrsEncodeToReplica() throws {
        let link = Mark.link(href: "https://example.com")
        let core = makeCore(.paragraph([.text("prose", marks: [link])]))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(canonical(try replicaRuns(doc)), [MarkedRun(text: "prose", marks: [link])])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Decode (Y → PM)

    func testJoinDecodesMarksFromReplica() throws {
        let doc = YDoc()
        try seedMarkedReplica(doc, [MarkedRun(text: "bold", marks: [.bold]), MarkedRun(text: "plain", marks: [])])
        let core = makeCore(.paragraph([]))
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(
            canonical(documentRuns(core)),
            canonical([MarkedRun(text: "bold", marks: [.bold]), MarkedRun(text: "plain", marks: [])])
        )
        XCTAssertEqual(core.lastTransaction?.origin, .remote)
        withExtendedLifetime(binding) {}
    }

    func testLinkMarkAttrsDecodeFromReplica() throws {
        let link = Mark.link(href: "https://example.com")
        let doc = YDoc()
        try seedMarkedReplica(doc, [MarkedRun(text: "prose", marks: [link])])
        let core = makeCore(.paragraph([]))
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(canonical(documentRuns(core)), [MarkedRun(text: "prose", marks: [link])])
        withExtendedLifetime(binding) {}
    }

    func testRemoteMarkToggleDecodesIntoDocument() async throws {
        let doc = YDoc()
        try seedMarkedReplica(doc, [MarkedRun(text: "hello", marks: [])])
        let core = makeCore(.paragraph([]))
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(canonical(documentRuns(core)), [MarkedRun(text: "hello", marks: [])])

        // A remote peer bolds the whole run.
        try remoteFormat(doc, marks: [.bold], from: 0, length: 5)
        for _ in 0..<10 where documentRuns(core).first?.marks.isEmpty != false {
            await Task.yield()
        }

        XCTAssertEqual(canonical(documentRuns(core)), [MarkedRun(text: "hello", marks: [.bold])])
        withExtendedLifetime(binding) {}
    }

    func testDecodeMarkSpanAcrossAdjacentSameMarkRuns() throws {
        // The document already holds two adjacent, separately-stored text nodes
        // that share a (empty) Mark set. A remote bold over the whole text must
        // mark BOTH nodes — a single Step across the node boundary would be
        // rejected by the Mark algebra, so the binding must split per node.
        let core = EditorCore(document: Document(.doc([.paragraph([.text("a"), .text("bc")])])))
        core.setSelection(TextSelection(anchor: 1, head: 1))
        let doc = YDoc()
        try seedMarkedReplica(doc, [MarkedRun(text: "abc", marks: [.bold])])
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        let runs = documentRuns(core)
        XCTAssertEqual(runs.map(\.text).joined(), "abc")
        XCTAssertTrue(runs.allSatisfy { $0.marks == [.bold] }, "every run must be bold; got \(runs)")
        withExtendedLifetime(binding) {}
    }

    func testRemoteMarkToggleOffDecodesIntoDocument() async throws {
        let doc = YDoc()
        try seedMarkedReplica(doc, [MarkedRun(text: "hello", marks: [.bold])])
        let core = makeCore(.paragraph([]))
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(canonical(documentRuns(core)), [MarkedRun(text: "hello", marks: [.bold])])

        // A remote peer clears bold over the run (format with a null value).
        let clear = try JSONSerialization.data(withJSONObject: ["bold": NSNull()])
        let fragment = try fragment(doc)
        try doc.write(origin: "remote-peer") { transaction in
            let textNode = try XCTUnwrap(Self.textNode(in: fragment, transaction: transaction))
            try transaction.format(textNode, at: 0, length: 5, attributesJSON: clear)
        }
        for _ in 0..<10 where documentRuns(core).first?.marks.isEmpty == false {
            await Task.yield()
        }

        XCTAssertEqual(canonical(documentRuns(core)), [MarkedRun(text: "hello", marks: [])])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Convergence

    func testTwoPeersConvergeWithMarks() async throws {
        let coreA = makeCore(.paragraph([.text("hi", marks: [.italic])]))
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore(.paragraph([]))
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()

        XCTAssertEqual(canonical(documentRuns(coreB)), [MarkedRun(text: "hi", marks: [.italic])])
        withExtendedLifetime((bindingA, bindingB)) {}
    }
}
