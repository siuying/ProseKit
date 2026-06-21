import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class YBindingOpaqueTests: XCTestCase {
    private func makeCore(_ blocks: [Node]) -> EditorCore {
        let core = EditorCore(document: Document(.doc(blocks)))
        core.setSelection(TextSelection(anchor: 1, head: 1))
        return core
    }

    private func fragment(_ doc: YDoc) throws -> YXmlFragment {
        try doc.xmlFragment(named: YBinding.defaultFragmentName)
    }

    /// Seeds [paragraph "a", image(src), paragraph "b"] where `image` is an atom
    /// (no children) — a node type ProseKit's Schema does not know.
    private func seedWithOpaqueNode(_ doc: YDoc) throws {
        let fragment = try fragment(doc)
        try doc.write(origin: "seed") { transaction in
            let p1 = try transaction.insertElement(named: "paragraph", into: fragment, at: 0)
            try transaction.insert("a", into: transaction.insertText(into: p1, at: 0), at: 0)
            let image = try transaction.insertElement(named: "image", into: fragment, at: 1)
            try transaction.setAttribute(.string("cat.png"), forKey: "src", in: image)
            let p2 = try transaction.insertElement(named: "paragraph", into: fragment, at: 2)
            try transaction.insert("b", into: transaction.insertText(into: p2, at: 0), at: 0)
        }
    }

    private func element(_ doc: YDoc, at index: UInt32) throws -> (tag: String, attrs: [String: Any], childCount: Int)? {
        let fragment = try fragment(doc)
        return try doc.read { transaction in
            guard case let .element(el) = try transaction.child(at: index, in: fragment) else { return nil }
            let attrs = (try? JSONSerialization.jsonObject(with: transaction.attributesJSON(from: el))) as? [String: Any] ?? [:]
            return (try transaction.tag(of: el), attrs, Int(try transaction.childCount(of: el)))
        }
    }

    // MARK: - Unknown nodes

    func testDecodesUnknownNodeAsOpaque() throws {
        let doc = YDoc()
        try seedWithOpaqueNode(doc)
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)

        binding.join()

        let blocks = core.document.root.content
        XCTAssertEqual(blocks.map(\.type), ["paragraph", "image", "paragraph"])
        XCTAssertEqual(blocks[1].attrs["src"], .string("cat.png"))
        XCTAssertTrue(blocks[1].content.isEmpty) // atom: no spurious children
        withExtendedLifetime(binding) {}
    }

    func testEditingNeighborPreservesUnknownNodeAndEmitsNoDelete() throws {
        let doc = YDoc()
        try seedWithOpaqueNode(doc)
        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        // Edit the first paragraph (a neighbor of the opaque node).
        let end = (core.document.position(ofNodeAtPath: [0]) ?? 0) + 1 + 1
        core.setSelection(TextSelection(anchor: end, head: end))
        try core.insertText("Z")

        XCTAssertEqual(core.document.plainText, "aZb")
        // The opaque image element is byte-for-byte intact: same tag, same attr,
        // still an atom (no text child was added), still present (not deleted).
        let image = try element(doc, at: 1)
        XCTAssertEqual(image?.tag, "image")
        XCTAssertEqual(image?.attrs["src"] as? String, "cat.png")
        XCTAssertEqual(image?.childCount, 0)
        // No delete: the fragment still has all three blocks.
        let fragment = try fragment(doc)
        let childCount = try doc.read { try $0.childCount(of: fragment) }
        XCTAssertEqual(childCount, 3)
        withExtendedLifetime(binding) {}
    }

    // MARK: - Unknown marks

    func testDecodesAndPreservesUnknownMarkKey() throws {
        let doc = YDoc()
        let fragment = try fragment(doc)
        // A run carrying a mark key ProseKit does not produce (an overlapping-mark
        // hashed key) plus a ychange key.
        let delta = Data(#"[{"insert":"hi","attributes":{"comment--AbCd1234":{"id":1},"bold":{}}}]"#.utf8)
        try doc.write(origin: "seed") { transaction in
            let paragraph = try transaction.insertElement(named: "paragraph", into: fragment, at: 0)
            let textNode = try transaction.insertText(into: paragraph, at: 0)
            try transaction.applyDeltaJSON(delta, to: textNode)
        }

        let core = makeCore([.paragraph([])])
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let marks = Set(core.document.root.content[0].content.first?.marks ?? [])
        XCTAssertTrue(marks.contains(Mark(type: "comment--AbCd1234", attrs: ["id": .int(1)])))
        XCTAssertTrue(marks.contains(.bold))
        withExtendedLifetime(binding) {}
    }
}
