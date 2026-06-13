import XCTest
@testable import ProseModel

/// Slice 03: split and join happen *within* a container (a blockquote), via the
/// path-addressed block-replace primitive.
final class NestedStructuralTests: XCTestCase {
    // doc > [ blockquote > [ p("ab"), p("cd") ], p("ef") ]
    private func makeDocument() -> Document {
        Document(.doc([
            .blockquote([.paragraph([.text("ab")]), .paragraph([.text("cd")])]),
            .paragraph([.text("ef")]),
        ]))
    }

    func testSplitInsideBlockquoteAddsASiblingWithinTheQuote() throws {
        // Split the first quoted paragraph between 'a' and 'b' (position 4).
        let edited = try SplitBlockStep(at: 4).apply(to: makeDocument()).document
        let quote = edited.root.content[0]
        XCTAssertEqual(quote.type, "blockquote")
        XCTAssertEqual(quote.content.map(\.plainText), ["a", "b", "cd"])
        XCTAssertEqual(edited.root.content[1].plainText, "ef", "top-level paragraph untouched")
        XCTAssertEqual(edited, Document(edited.root), "index matches rebuild")
    }

    func testJoinInsideBlockquoteMergesIntoPreviousSibling() throws {
        // Join the second quoted paragraph (textStart 7) into the first.
        let edited = try JoinBlocksStep(at: 7).apply(to: makeDocument()).document
        let quote = edited.root.content[0]
        XCTAssertEqual(quote.content.map(\.plainText), ["abcd"])
        XCTAssertEqual(edited.root.content[1].plainText, "ef")
        XCTAssertEqual(edited, Document(edited.root))
    }

    func testEmptyQuotedBlockJoinIsRemoved() throws {
        let document = Document(.doc([
            .blockquote([.paragraph([.text("ab")]), .paragraph([])]),
            .paragraph([.text("ef")]),
        ]))
        // The empty second quoted block starts at position 7.
        let edited = try JoinBlocksStep(at: 7).apply(to: document).document
        XCTAssertEqual(edited.root.content[0].content.map(\.plainText), ["ab"])
        XCTAssertEqual(edited, Document(edited.root))
    }

    func testCanJoinBackwardRespectsContainerSiblings() {
        let document = makeDocument()
        // First quoted block (childIndex 0) cannot join backward — it lifts.
        XCTAssertFalse(document.canJoinBackward(at: 3))
        // Second quoted block (childIndex 1) can join into the first.
        XCTAssertTrue(document.canJoinBackward(at: 7))
    }

    func testSplitThenInverseJoinRoundTrips() throws {
        let document = makeDocument()
        let split = SplitBlockStep(at: 4)
        let after = try split.apply(to: document).document
        let inverse = try split.inverted(in: document)
        let restored = try inverse.apply(to: after).document
        XCTAssertEqual(restored, document, "split then its inverse join restores the document")
    }

    func testFlatSplitAndJoinStillWork() throws {
        let flat = Document(.doc([.paragraph([.text("ab")]), .paragraph([.text("cd")])]))
        let split = try SplitBlockStep(at: 3).apply(to: flat).document // between a,b at top level
        XCTAssertEqual(split.root.content.map(\.plainText), ["a", "b", "cd"])
        let joined = try JoinBlocksStep(at: 6).apply(to: flat).document // cd start is 6
        XCTAssertEqual(joined.root.content.map(\.plainText), ["abcd"])
    }
}
