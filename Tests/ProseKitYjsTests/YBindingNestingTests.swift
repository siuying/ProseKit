import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingNestingTests: XCTestCase {
    private func makeCore(_ blocks: [Node]) -> EditorCore {
        let core = EditorCore(document: Document(.doc(blocks)))
        core.setSelection(TextSelection(anchor: 1, head: 1))
        return core
    }

    private func fragment(_ doc: YDoc) throws -> YXmlFragment {
        try doc.xmlFragment(named: YBinding.defaultFragmentName)
    }

    // Seeds a replica from a Node tree (recursively), without a binding.
    private func seed(_ doc: YDoc, _ blocks: [Node]) throws {
        let fragment = try fragment(doc)
        try doc.write(origin: "seed") { transaction in
            try seedChildren(into: fragment, blocks, transaction)
        }
    }

    private func seedChildren(into container: YXmlContainer, _ nodes: [Node], _ transaction: YWriteTransaction) throws {
        for (index, node) in nodes.enumerated() {
            let element = try transaction.insertElement(named: node.type, into: container, at: UInt32(index))
            for (key, value) in node.attrs where value != .null {
                if case let .int(int) = value { try transaction.setAttribute(.int(Int64(int)), forKey: key, in: element) }
                else if case let .string(string) = value { try transaction.setAttribute(.string(string), forKey: key, in: element) }
                else if case let .bool(bool) = value { try transaction.setAttribute(.bool(bool), forKey: key, in: element) }
            }
            if node.isTextblock {
                let textNode = try transaction.insertText(into: element, at: 0)
                try transaction.applyDeltaJSON(MarkedText(textblock: node).deltaJSON(), to: textNode)
            } else {
                try seedChildren(into: element, node.content, transaction)
            }
        }
    }

    // Decodes the replica back to a Node tree (types + text only) for comparison.
    private func decodeReplica(_ doc: YDoc) throws -> [Node] {
        let fragment = try fragment(doc)
        return try doc.read { try decodeChildren($0, fragment) }
    }

    private func decodeChildren(_ transaction: YReadTransaction, _ container: YXmlContainer) throws -> [Node] {
        let count = try transaction.childCount(of: container)
        return try (0..<count).compactMap { index -> Node? in
            guard case let .element(element) = try transaction.child(at: index, in: container) else { return nil }
            let type = try transaction.tag(of: element)
            let childCount = try transaction.childCount(of: element)
            if childCount > 0, case let .text(textNode) = try transaction.child(at: 0, in: element) {
                let runs = MarkedText(deltaJSON: try transaction.deltaJSON(from: textNode)).runs
                return Node(type: type, content: runs.map { Node.text($0.text, marks: $0.marks) })
            }
            return Node(type: type, content: try decodeChildren(transaction, element))
        }
    }

    private func bulletList(_ items: [String]) -> Node {
        .bulletList(items.map { .listItem([.paragraph([.text($0)])]) })
    }

    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    // MARK: - Encode

    func testEncodesNestedListToReplica() throws {
        let core = makeCore([bulletList(["a", "b"])])
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        // Strip marks for structural comparison.
        XCTAssertEqual(try decodeReplica(doc), [bulletList(["a", "b"])])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Decode

    func testDecodesNestedListFromReplica() throws {
        let doc = YDoc()
        try seed(doc, [bulletList(["one", "two"])])
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(core.document.root.content, [bulletList(["one", "two"])])
        XCTAssertEqual(core.lastTransaction?.origin, .remote)
        withExtendedLifetime(binding) {}
    }

    func testRemoteListItemInsertDecodes() async throws {
        let doc = YDoc()
        try seed(doc, [bulletList(["a", "b"])])
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(core.document.root.content, [bulletList(["a", "b"])])

        // A remote peer inserts a third list item between a and b.
        let fragment = try fragment(doc)
        try doc.write(origin: "remote-peer") { transaction in
            guard case let .element(list) = try transaction.child(at: 0, in: fragment) else { return }
            let item = try transaction.insertElement(named: "listItem", into: list, at: 1)
            let paragraph = try transaction.insertElement(named: "paragraph", into: item, at: 0)
            let textNode = try transaction.insertText(into: paragraph, at: 0)
            try transaction.insert("mid", into: textNode, at: 0)
        }
        for _ in 0..<10 where core.document.plainText != "amidb" { await Task.yield() }

        XCTAssertEqual(core.document.root.content, [bulletList(["a", "mid", "b"])])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Concurrency

    func testConcurrentEditsInDifferentItemsBothSurvive() async throws {
        let coreA = makeCore([bulletList(["a", "b"])])
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore([.paragraph([])])
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()
        XCTAssertEqual(coreB.document.root.content, [bulletList(["a", "b"])])

        // A edits the first item, B edits the second — concurrently.
        let aTextEnd = (coreA.document.position(ofNodeAtPath: [0, 0, 0]) ?? 0) + 1 + 1
        coreA.setSelection(TextSelection(anchor: aTextEnd, head: aTextEnd))
        try coreA.insertText("X")

        let bTextEnd = (coreB.document.position(ofNodeAtPath: [0, 1, 0]) ?? 0) + 1 + 1
        coreB.setSelection(TextSelection(anchor: bTextEnd, head: bTextEnd))
        try coreB.insertText("Y")

        try sync(docA, docB)
        for _ in 0..<10 where coreA.document.plainText != coreB.document.plainText { await Task.yield() }

        XCTAssertEqual(coreA.document.root.content, coreB.document.root.content)
        XCTAssertTrue(coreA.document.plainText.contains("aX"))
        XCTAssertTrue(coreA.document.plainText.contains("bY"))
        withExtendedLifetime((bindingA, bindingB)) {}
    }
}
