import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingTests: XCTestCase {
    // MARK: - Helpers

    private func makeCore(_ text: String) -> EditorCore {
        let core = EditorCore(document: Document(.doc([.paragraph(text.isEmpty ? [] : [.text(text)])])))
        core.setSelection(TextSelection(anchor: 2 + text.count, head: 2 + text.count))
        return core
    }

    /// Reads the binding's single-paragraph plain text out of a replica.
    private func replicaText(_ doc: YDoc) throws -> String {
        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        return try doc.read { transaction -> String in
            guard try transaction.childCount(of: fragment) > 0,
                  case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
                  try transaction.childCount(of: paragraph) > 0,
                  case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
            else { return "" }
            return try transaction.string(from: textNode)
        }
    }

    /// Pre-seeds a replica directly (no binding attached, so no echo).
    private func seedReplica(_ doc: YDoc, _ text: String) throws {
        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        try doc.write(origin: "seed") { transaction in
            let paragraph = try transaction.insertElement(named: "paragraph", into: fragment, at: 0)
            let textNode = try transaction.insertText(into: paragraph, at: 0)
            if !text.isEmpty {
                try transaction.insert(text, into: textNode, at: 0)
            }
        }
    }

    /// A remote-origin insert into an existing paragraph's text node.
    private func remoteInsert(_ doc: YDoc, _ text: String, at index: UInt32) throws {
        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        try doc.write(origin: "remote-peer") { transaction in
            guard case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
                  case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
            else { return XCTFail("expected paragraph > text") }
            try transaction.insert(text, into: textNode, at: index)
        }
    }

    /// Exchanges full state both ways, exactly as a provider's sync would.
    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    // MARK: - Join

    func testJoinSeedsEmptyReplicaFromDocument() throws {
        let core = makeCore("hello")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(try replicaText(doc), "hello")
    }

    func testJoinResetsDocumentFromNonEmptyReplica() throws {
        let doc = YDoc()
        try seedReplica(doc, "remote")
        let core = makeCore("")
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(core.document.plainText, "remote")
        XCTAssertEqual(core.lastTransaction?.origin, .remote)
    }

    func testJoinIsIdempotent() throws {
        let core = makeCore("a")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()
        binding.join()

        XCTAssertEqual(try replicaText(doc), "a")
    }

    // MARK: - Encode (PM → Y)

    func testLocalEditEncodesToReplica() throws {
        let core = makeCore("")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        try core.insertText("hi")

        XCTAssertEqual(try replicaText(doc), "hi")
    }

    func testLocalEditBeforeJoinDoesNotEncode() throws {
        let core = makeCore("")
        let doc = YDoc()
        _ = YBinding(core: core, doc: doc)

        try core.insertText("hi")

        XCTAssertEqual(try replicaText(doc), "")
    }

    // MARK: - Decode (Y → PM) + loop break

    func testRemoteChangeDecodesIntoDocument() throws {
        let core = makeCore("hi")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        try remoteInsert(doc, " there", at: 2)

        XCTAssertEqual(core.document.plainText, "hi there")
        XCTAssertEqual(core.lastTransaction?.origin, .remote)
    }

    func testLocalEditDoesNotEchoAsSelfApply() throws {
        let core = makeCore("")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        try core.insertText("ab")

        // No doubling from a self-echo, and the last transaction stayed local.
        XCTAssertEqual(try replicaText(doc), "ab")
        XCTAssertEqual(core.document.plainText, "ab")
        XCTAssertEqual(core.lastTransaction?.origin, .local)
    }

    // MARK: - Selection survival

    func testRemoteInsertBeforeCaretKeepsCaretOnSameCharacter() throws {
        let core = makeCore("world")
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        core.setSelection(TextSelection(anchor: 3, head: 3)) // caret after "w"

        try remoteInsert(doc, "XY", at: 0) // prepend before the caret

        XCTAssertEqual(core.document.plainText, "XYworld")
        XCTAssertEqual(core.selection.head, 5) // still right after "w"
    }

    // MARK: - Two-peer convergence

    func testTwoPeersConvergeOnConcurrentTyping() throws {
        // Peer A joins an empty replica and seeds the first paragraph.
        let coreA = makeCore("")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()
        try coreA.insertText("Hello")

        // Peer B joins after the replica is non-empty (server-mediated join).
        let coreB = makeCore("")
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()
        XCTAssertEqual(coreB.document.plainText, "Hello")

        // Concurrent edits on both peers, no sync in between.
        coreA.setSelection(TextSelection(anchor: 7, head: 7))
        try coreA.insertText(" A")
        coreB.setSelection(TextSelection(anchor: 7, head: 7))
        try coreB.insertText(" B")

        try sync(docA, docB)

        XCTAssertEqual(coreA.document.plainText, coreB.document.plainText)
        XCTAssertFalse(coreA.document.plainText.isEmpty)
        XCTAssertTrue(coreA.document.plainText.contains("A"))
        XCTAssertTrue(coreA.document.plainText.contains("B"))
    }

    // MARK: - Fragment name

    func testMismatchedFragmentNamesDoNotConverge() throws {
        let coreA = makeCore("hi")
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA, fragmentName: "prosemirror")
        bindingA.join()

        let coreB = makeCore("")
        let docB = YDoc()
        let bindingB = YBinding(core: coreB, doc: docB, fragmentName: "default")
        try sync(docA, docB)
        bindingB.join()

        XCTAssertEqual(coreB.document.plainText, "")
    }
}
