import XCTest
@testable import ProseModel

/// Slice 04 editing: list item editing operates at the listItem sibling level,
/// not by splitting the paragraph inside the existing item.
final class ListItemStructuralTests: XCTestCase {
    private func makeDocument() -> Document {
        Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("ab")])]),
                .listItem([.paragraph([.text("cd")])]),
            ]),
            .paragraph([.text("ef")]),
        ]))
    }

    func testSplitListItemCreatesANewSiblingItem() throws {
        // Split the first item's paragraph between "a" and "b" (position 5).
        let edited = try SplitListItemStep(at: 5).apply(to: makeDocument()).document
        let list = edited.root.content[0]
        XCTAssertEqual(list.type, "bulletList")
        XCTAssertEqual(list.content.map(\.type), ["listItem", "listItem", "listItem"])
        XCTAssertEqual(list.content.map(\.plainText), ["a", "b", "cd"])
        XCTAssertEqual(edited.root.content[1].plainText, "ef", "top-level paragraph untouched")
        XCTAssertEqual(edited, Document(edited.root), "index matches rebuild")
    }

    func testSplitListItemThenInverseJoinRoundTrips() throws {
        let document = makeDocument()
        let split = SplitListItemStep(at: 5)
        let after = try split.apply(to: document).document
        let inverse = try split.inverted(in: document)
        let restored = try inverse.apply(to: after).document
        XCTAssertEqual(restored, document, "split item then its inverse join restores the document")
    }

    func testLiftFirstListItemOutBeforeRemainingList() throws {
        let lifted = try LiftListItemStep(at: 4).apply(to: makeDocument()).document
        XCTAssertEqual(lifted.root.content.map(\.type), ["paragraph", "bulletList", "paragraph"])
        XCTAssertEqual(lifted.root.content[0].plainText, "ab")
        XCTAssertEqual(lifted.root.content[1].content.map(\.plainText), ["cd"])
        XCTAssertEqual(lifted.root.content[2].plainText, "ef")
        XCTAssertEqual(lifted, Document(lifted.root), "index matches rebuild")
    }

    func testLiftOnlyListItemRemovesList() throws {
        let document = Document(.doc([
            .bulletList([.listItem([.paragraph([.text("solo")])])]),
            .paragraph([.text("after")]),
        ]))
        let lifted = try LiftListItemStep(at: 4).apply(to: document).document
        XCTAssertEqual(lifted.root.content.map(\.type), ["paragraph", "paragraph"])
        XCTAssertEqual(lifted.root.content.map(\.plainText), ["solo", "after"])
    }

    func testLiftListItemThenInverseRoundTrips() throws {
        let document = makeDocument()
        let lift = LiftListItemStep(at: 4)
        let lifted = try lift.apply(to: document).document
        let inverse = try lift.inverted(in: document)
        let restored = try inverse.apply(to: lifted).document
        XCTAssertEqual(restored, document, "lift item then its inverse restores the document")
    }

    func testWrapParagraphInBulletListThenInverseRoundTrips() throws {
        let document = Document(.doc([
            .paragraph([.text("item")]),
            .paragraph([.text("after")]),
        ]))
        let wrap = WrapInListStep(blockRange: 1..<7, listType: "bulletList")
        let wrapped = try wrap.apply(to: document).document
        XCTAssertEqual(wrapped.root.content[0].type, "bulletList")
        XCTAssertEqual(wrapped.root.content[0].content.map(\.type), ["listItem"])
        XCTAssertEqual(wrapped.root.content[0].plainText, "item")
        let inverse = try wrap.inverted(in: document)
        let restored = try inverse.apply(to: wrapped).document
        XCTAssertEqual(restored, document)
    }
}
