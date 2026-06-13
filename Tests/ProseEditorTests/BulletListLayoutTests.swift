import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Slice 04 (render): a bullet list lays out as nested container boxes
/// (bulletList → listItem → paragraph), the leaves flatten in order, and the
/// item paragraphs are indented to leave room for the marker.
final class BulletListLayoutTests: XCTestCase {
    private func layout() throws -> LayoutBox {
        let document = Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("first")])]),
                .listItem([.paragraph([.text("second")])]),
            ]),
            .paragraph([.text("after")]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 320)
        return try store.layout(document)
    }

    func testLayoutNestsBulletListContainers() throws {
        let root = try layout()
        XCTAssertEqual(root.children.count, 2)
        let list = root.children[0]
        XCTAssertEqual(list.node.type, "bulletList")
        XCTAssertEqual(list.children.map { $0.node.type }, ["listItem", "listItem"])
        XCTAssertEqual(list.children[0].children[0].node.plainText, "first")
    }

    func testLeavesFlattenAcrossListItems() throws {
        let root = try layout()
        XCTAssertEqual(root.leaves.map { $0.node.plainText }, ["first", "second", "after"])
    }

    func testItemParagraphsAreIndentedForTheMarker() throws {
        let root = try layout()
        let indent = containerIndent(forType: "listItem")
        let firstParagraph = root.children[0].children[0].children[0]
        XCTAssertEqual(firstParagraph.frame.minX, indent)
        XCTAssertEqual(root.children[1].frame.minX, 0, "trailing top-level paragraph not indented")
    }

    func testCaretInsideAListItemRoundTrips() throws {
        let root = try layout()
        let mapper = GeometryMapper()
        // "first" starts at position 4 (doc>bulletList open 1, listItem open 2, paragraph open 3, text 4).
        let caret = mapper.caretRect(for: 4, in: root)
        XCTAssertEqual(caret.minX, containerIndent(forType: "listItem"), accuracy: 0.5)
        let hit = mapper.closestPosition(to: CGPoint(x: caret.midX, y: caret.midY), in: root)
        XCTAssertTrue(root.leaves[0].positionRange.contains(hit))
    }

    func testBulletListValidatesAndRoundTripsThroughJSON() throws {
        let document = Document(.doc([
            .bulletList([.listItem([.paragraph([.text("x")])])]),
        ]))
        XCTAssertNoThrow(try Schema.slice1.validate(document))
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(decoded, document)
    }

    func testOrderedListValidatesAndRoundTripsThroughJSON() throws {
        let document = Document(.doc([
            .orderedList(start: 3, [.listItem([.paragraph([.text("third")])])]),
        ]))
        XCTAssertNoThrow(try Schema.slice1.validate(document))
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(decoded, document)
    }

    func testOrderedListLayoutsLikeAListContainer() throws {
        let document = Document(.doc([
            .orderedList([
                .listItem([.paragraph([.text("first")])]),
                .listItem([.paragraph([.text("second")])]),
            ]),
        ]))
        var store = IncrementalLayoutStore(schema: .slice1, width: 320)
        let root = try store.layout(document)
        XCTAssertEqual(root.children[0].node.type, "orderedList")
        XCTAssertEqual(root.children[0].children.map { $0.node.type }, ["listItem", "listItem"])
        XCTAssertEqual(root.leaves.map { $0.node.plainText }, ["first", "second"])
    }
}
