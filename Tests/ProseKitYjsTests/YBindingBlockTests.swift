import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingBlockTests: XCTestCase {
    private func makeCore(_ blocks: [Node]) -> EditorCore {
        let core = EditorCore(document: Document(.doc(blocks)))
        core.setSelection(TextSelection(anchor: 1, head: 1))
        return core
    }

    private func fragment(_ doc: YDoc) throws -> YXmlFragment {
        try doc.xmlFragment(named: YBinding.defaultFragmentName)
    }

    private func yValue(_ value: Any) -> YValue {
        switch value {
        case let int as Int: return .int(Int64(int))
        case let string as String: return .string(string)
        case let bool as Bool: return .bool(bool)
        default: return .undefined
        }
    }

    private func seedBlocks(_ doc: YDoc, _ blocks: [(type: String, attrs: [String: Any], text: String)]) throws {
        let fragment = try fragment(doc)
        try doc.write(origin: "seed") { transaction in
            for (index, block) in blocks.enumerated() {
                let element = try transaction.insertElement(named: block.type, into: fragment, at: UInt32(index))
                for (key, value) in block.attrs {
                    try transaction.setAttribute(yValue(value), forKey: key, in: element)
                }
                let textNode = try transaction.insertText(into: element, at: 0)
                if !block.text.isEmpty {
                    try transaction.insert(block.text, into: textNode, at: 0)
                }
            }
        }
    }

    private func replicaTags(_ doc: YDoc) throws -> [String] {
        let fragment = try fragment(doc)
        return try doc.read { transaction in
            let count = try transaction.childCount(of: fragment)
            return try (0..<count).compactMap { index -> String? in
                guard case let .element(element) = try transaction.child(at: index, in: fragment) else { return nil }
                return try transaction.tag(of: element)
            }
        }
    }

    private func replicaAttrs(_ doc: YDoc, at index: UInt32) throws -> [String: Any] {
        let fragment = try fragment(doc)
        return try doc.read { transaction -> [String: Any] in
            guard case let .element(element) = try transaction.child(at: index, in: fragment) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: transaction.attributesJSON(from: element))) as? [String: Any] ?? [:]
        }
    }

    private func documentTypes(_ core: EditorCore) -> [String] {
        core.document.root.content.map(\.type)
    }

    // MARK: - Encode (PM → Y)

    func testJoinEncodesBlockTypesAndAttrs() throws {
        let core = makeCore([
            .heading(level: 2, [.text("Title")]),
            .paragraph([.text("body")]),
        ])
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(try replicaTags(doc), ["heading", "paragraph"])
        XCTAssertEqual((try replicaAttrs(doc, at: 0)["level"] as? NSNumber)?.intValue, 2)
        withExtendedLifetime(binding) {}
    }

    func testLocalBlockTypeToggleEncodesToReplica() throws {
        let core = makeCore([.paragraph([.text("x")])])
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(try replicaTags(doc), ["paragraph"])

        // Turn the paragraph into a heading (a different nodeName → element replaced).
        XCTAssertTrue(core.run(Commands.toggleHeading(level: 1)))
        XCTAssertEqual(try replicaTags(doc), ["heading"])
        XCTAssertEqual((try replicaAttrs(doc, at: 0)["level"] as? NSNumber)?.intValue, 1)
        withExtendedLifetime(binding) {}
    }

    // MARK: - Decode (Y → PM)

    func testJoinDecodesBlockTypesAndAttrs() throws {
        let doc = YDoc()
        try seedBlocks(doc, [
            (type: "heading", attrs: ["level": 3], text: "Title"),
            (type: "paragraph", attrs: [:], text: "body"),
        ])
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        XCTAssertEqual(documentTypes(core), ["heading", "paragraph"])
        XCTAssertEqual(core.document.root.content[0].attrs["level"], .int(3))
        XCTAssertEqual(core.document.plainText, "Titlebody")
        withExtendedLifetime(binding) {}
    }

    func testRemoteBlockTypeToggleDecodes() async throws {
        let doc = YDoc()
        try seedBlocks(doc, [(type: "paragraph", attrs: [:], text: "x")])
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(documentTypes(core), ["paragraph"])

        // Remote peer replaces the paragraph element with a heading carrying "x".
        let fragment = try fragment(doc)
        try doc.write(origin: "remote-peer") { transaction in
            try transaction.remove(from: fragment, at: 0, length: 1)
            let heading = try transaction.insertElement(named: "heading", into: fragment, at: 0)
            try transaction.setAttribute(.int(1), forKey: "level", in: heading)
            let textNode = try transaction.insertText(into: heading, at: 0)
            try transaction.insert("x", into: textNode, at: 0)
        }
        for _ in 0..<10 where documentTypes(core) != ["heading"] { await Task.yield() }

        XCTAssertEqual(documentTypes(core), ["heading"])
        XCTAssertEqual(core.document.plainText, "x")
        withExtendedLifetime(binding) {}
    }

    func testRemoteAttrEditDecodesInPlace() async throws {
        let doc = YDoc()
        try seedBlocks(doc, [(type: "heading", attrs: ["level": 1], text: "h")])
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(core.document.root.content[0].attrs["level"], .int(1))

        // Remote bumps the heading level (attribute change on the existing element).
        let fragment = try fragment(doc)
        try doc.write(origin: "remote-peer") { transaction in
            guard case let .element(heading) = try transaction.child(at: 0, in: fragment) else { return }
            try transaction.setAttribute(.int(3), forKey: "level", in: heading)
        }
        for _ in 0..<10 where core.document.root.content.first?.attrs["level"] != .int(3) { await Task.yield() }

        XCTAssertEqual(core.document.root.content[0].attrs["level"], .int(3))
        XCTAssertEqual(documentTypes(core), ["heading"])
        withExtendedLifetime(binding) {}
    }

    func testNullAttrRemovesFromReplica() throws {
        // textAlign present, then cleared (null) → attribute is removed.
        let core = makeCore([.paragraph([.text("x")])])
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        XCTAssertTrue(core.run(Commands.setTextAlign("center")))
        XCTAssertEqual(try replicaAttrs(doc, at: 0)["textAlign"] as? String, "center")

        XCTAssertTrue(core.run(Commands.setTextAlign(nil)))
        XCTAssertNil(try replicaAttrs(doc, at: 0)["textAlign"])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Concurrency: in-place attr mutation preserves a concurrent text edit

    func testConcurrentAttrAndTextEditBothSurvive() async throws {
        let coreA = makeCore([.paragraph([.text("Hello")])])
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = makeCore([.paragraph([])])
        let docB = YDoc()
        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()
        XCTAssertEqual(coreB.document.plainText, "Hello")

        // A changes the block's alignment in place (the same shape the binding's
        // in-place encode produces: setAttribute on the existing element, never a
        // delete+recreate); B concurrently edits the element's text. Because the
        // element is mutated rather than replaced, both edits survive the merge.
        let fragmentA = try fragment(docA)
        try docA.write(origin: "peer-a") { transaction in
            guard case let .element(paragraph) = try transaction.child(at: 0, in: fragmentA) else { return }
            try transaction.setAttribute(.string("center"), forKey: "textAlign", in: paragraph)
        }
        let end = coreB.document.endTextPosition
        coreB.setSelection(TextSelection(anchor: end, head: end))
        try coreB.insertText("!")

        try docB.apply(docA.encodeStateAsUpdateV1(from: docB.stateVector()))
        try docA.apply(docB.encodeStateAsUpdateV1(from: docA.stateVector()))
        for _ in 0..<10 where !coreB.document.plainText.contains("!")
            || coreB.document.root.content.first?.attrs["textAlign"] != .string("center") {
            await Task.yield()
        }

        XCTAssertTrue(coreB.document.plainText.contains("Hello"))
        XCTAssertTrue(coreB.document.plainText.contains("!"))
        XCTAssertEqual(coreB.document.root.content[0].attrs["textAlign"], .string("center"))
        withExtendedLifetime((bindingA, bindingB)) {}
    }
}
