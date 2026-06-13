import XCTest
@testable import ProseModel

/// Slice 03 (wrap/unwrap): wrapping a block into a container and lifting it back
/// out are inverses, at the top level and inside an existing container.
final class WrapLiftTests: XCTestCase {
    func testWrapTopLevelParagraphIntoBlockquote() throws {
        let document = Document(.doc([.paragraph([.text("hello")]), .paragraph([.text("after")])]))
        // First paragraph node range is 1..<8 (open 1, "hello" 2..6, close 7).
        let wrapped = try WrapInStep(blockRange: 1..<8, containerType: "blockquote").apply(to: document).document
        XCTAssertEqual(wrapped.root.content[0].type, "blockquote")
        XCTAssertEqual(wrapped.root.content[0].content.map(\.plainText), ["hello"])
        XCTAssertEqual(wrapped.root.content[1].plainText, "after")
        XCTAssertEqual(wrapped, Document(wrapped.root), "index matches rebuild")
    }

    func testWrapThenLiftRoundTrips() throws {
        let document = Document(.doc([.paragraph([.text("hello")]), .paragraph([.text("after")])]))
        let wrap = WrapInStep(blockRange: 1..<8, containerType: "blockquote")
        let wrapped = try wrap.apply(to: document).document
        let lift = try wrap.inverted(in: document)
        let restored = try lift.apply(to: wrapped).document
        XCTAssertEqual(restored, document, "wrap then its inverse lift restores the document")
    }

    func testLiftFirstChildOutOfBlockquoteKeepingRest() throws {
        // doc > [ blockquote > [ p("a"), p("b") ], p("c") ]
        let document = Document(.doc([
            .blockquote([.paragraph([.text("a")]), .paragraph([.text("b")])]),
            .paragraph([.text("c")]),
        ]))
        // First quoted paragraph p("a") node range: blockquote opens at 1, p("a")
        // at 2..<5 (open 2, "a" 3, close 4).
        let lifted = try LiftStep(blockRange: 2..<5).apply(to: document).document
        // p("a") lifts out before the blockquote; the quote keeps p("b").
        XCTAssertEqual(lifted.root.content.map(\.type), ["paragraph", "blockquote", "paragraph"])
        XCTAssertEqual(lifted.root.content[0].plainText, "a")
        XCTAssertEqual(lifted.root.content[1].content.map(\.plainText), ["b"])
        XCTAssertEqual(lifted.root.content[2].plainText, "c")
        XCTAssertEqual(lifted, Document(lifted.root))
    }

    func testLiftOnlyChildRemovesTheContainer() throws {
        let document = Document(.doc([
            .blockquote([.paragraph([.text("solo")])]),
            .paragraph([.text("after")]),
        ]))
        // The sole quoted paragraph: blockquote opens at 1, p("solo") at 2..<8.
        let lifted = try LiftStep(blockRange: 2..<8).apply(to: document).document
        XCTAssertEqual(lifted.root.content.map(\.type), ["paragraph", "paragraph"])
        XCTAssertEqual(lifted.root.content.map(\.plainText), ["solo", "after"])
        XCTAssertEqual(lifted, Document(lifted.root))
    }

    func testLiftThenWrapRoundTripsForOnlyChild() throws {
        let document = Document(.doc([
            .blockquote([.paragraph([.text("solo")])]),
            .paragraph([.text("after")]),
        ]))
        let lift = LiftStep(blockRange: 2..<8)
        let lifted = try lift.apply(to: document).document
        let wrap = try lift.inverted(in: document)
        let restored = try wrap.apply(to: lifted).document
        XCTAssertEqual(restored, document, "lift then its inverse wrap restores the document")
    }
}
