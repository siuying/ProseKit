import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Slice 01: a nested document (blockquote) lays out as a container box wrapping
/// indented leaf boxes, the leaf list flattens in document order, and geometry
/// places the caret inside the nested blocks.
final class NestedLayoutTests: XCTestCase {
    private func layout() throws -> LayoutBox {
        let document = Document(.doc([
            .blockquote([.paragraph([.text("alpha")]), .paragraph([.text("beta")])]),
            .paragraph([.text("gamma")]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 240)
        return try store.layout(document)
    }

    func testLayoutTreeNestsAContainerBox() throws {
        let root = try layout()
        XCTAssertEqual(root.children.count, 2)
        let quote = root.children[0]
        XCTAssertEqual(quote.kind, .container)
        XCTAssertEqual(quote.node.type, "blockquote")
        XCTAssertEqual(quote.children.count, 2)
        XCTAssertEqual(quote.children.map { $0.node.plainText }, ["alpha", "beta"])
        XCTAssertEqual(root.children[1].kind, .leafBlock)
        XCTAssertEqual(root.children[1].node.plainText, "gamma")
    }

    func testLeavesFlattenInDocumentOrder() throws {
        let root = try layout()
        XCTAssertEqual(root.leaves.map { $0.node.plainText }, ["alpha", "beta", "gamma"])
        // Position ranges match the leaf-block tiling (alpha 2..<9, beta 9..<15,
        // gamma 16..<23 — the blockquote close token is the gap at 15..16).
        XCTAssertEqual(root.leaves[0].positionRange, 2..<9)
        XCTAssertEqual(root.leaves[1].positionRange, 9..<15)
        XCTAssertEqual(root.leaves[2].positionRange, 16..<23)
    }

    func testQuotedContentIsIndentedAndTopLevelIsNot() throws {
        let root = try layout()
        XCTAssertEqual(root.children[0].frame.minX, 0, "the blockquote box spans from the left margin")
        XCTAssertEqual(root.children[0].children[0].frame.minX, containerIndent(forType: "blockquote"))
        XCTAssertEqual(root.children[1].frame.minX, 0, "top-level paragraph is not indented")
    }

    func testCaretInsideBlockquoteIsIndentedAndRoundTrips() throws {
        let root = try layout()
        let mapper = GeometryMapper()
        // Position 3 is the first character of "alpha", inside the blockquote.
        let caret = mapper.caretRect(for: 3, in: root)
        XCTAssertEqual(caret.minX, containerIndent(forType: "blockquote"), accuracy: 0.5)
        // A point inside "alpha" resolves back to a Position inside its range.
        let hit = mapper.closestPosition(to: CGPoint(x: caret.midX, y: caret.midY), in: root)
        XCTAssertTrue(root.leaves[0].positionRange.contains(hit), "hit \(hit) should land in alpha")
    }

    func testCaretInTopLevelParagraphBelowTheQuote() throws {
        let root = try layout()
        let mapper = GeometryMapper()
        let caret = mapper.caretRect(for: 17, in: root) // inside "gamma"
        XCTAssertEqual(caret.minX, 0, accuracy: 0.5)
        XCTAssertGreaterThan(caret.minY, root.children[0].frame.maxY - 1, "gamma sits below the quote")
    }
}
