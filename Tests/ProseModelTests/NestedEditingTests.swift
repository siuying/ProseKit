import XCTest
@testable import ProseModel

/// Slice 02: text edits inside a leaf block that lives in a container behave
/// exactly like the same edit in a top-level paragraph, and the index stays
/// correct (matches a from-scratch rebuild).
final class NestedEditingTests: XCTestCase {
    // doc > [ blockquote > [ p("ab"), p("cd") ], p("ef") ]
    private func makeDocument() -> Document {
        Document(.doc([
            .blockquote([.paragraph([.text("ab")]), .paragraph([.text("cd")])]),
            .paragraph([.text("ef")]),
        ]))
    }

    func testInsertInsideBlockquote() throws {
        let document = makeDocument()
        // Position 4 is between 'a' and 'b' in the first quoted paragraph.
        let edited = try ReplaceStep(from: 4, to: 4, insertText: "X").apply(to: document).document
        XCTAssertEqual(edited.plainText(from: edited.startTextPosition, to: edited.endTextPosition), "aXb\ncd\nef")
        XCTAssertEqual(edited.root.content[0].content[0].plainText, "aXb")
        XCTAssertEqual(edited, Document(edited.root), "index matches a from-scratch rebuild")
    }

    func testDeleteInsideBlockquote() throws {
        let document = makeDocument()
        let edited = try ReplaceStep(from: 3, to: 4, insertText: "").apply(to: document).document // delete 'a'
        XCTAssertEqual(edited.plainText(from: edited.startTextPosition, to: edited.endTextPosition), "b\ncd\nef")
        XCTAssertEqual(edited, Document(edited.root))
    }

    func testMarkedInsertInsideBlockquoteCarriesTheMark() throws {
        let document = makeDocument()
        let edited = try ReplaceStep(from: 4, to: 4, insertText: "Z", insertMarks: [.bold]).apply(to: document).document
        let firstQuoted = edited.root.content[0].content[0]
        XCTAssertEqual(firstQuoted.plainText, "aZb")
        // The inserted run carries bold; the surrounding text does not.
        let boldRuns = firstQuoted.content.filter { $0.marks.contains(.bold) }
        XCTAssertEqual(boldRuns.map(\.text), ["Z"])
        XCTAssertEqual(edited, Document(edited.root))
    }

    func testEditingTheTopLevelParagraphBelowTheQuote() throws {
        let document = makeDocument()
        // 'ef' starts at position 12; insert between e and f.
        let edited = try ReplaceStep(from: 13, to: 13, insertText: "Y").apply(to: document).document
        XCTAssertEqual(edited.root.content[1].plainText, "eYf")
        XCTAssertEqual(edited.plainText(from: edited.startTextPosition, to: edited.endTextPosition), "ab\ncd\neYf")
        XCTAssertEqual(edited, Document(edited.root))
    }

    func testNestedEditMatchesTheEquivalentFlatEdit() throws {
        // Inserting at the same in-paragraph offset (between 'a' and 'b')
        // produces the same text whether the paragraph is quoted or top level —
        // the algebra is depth-agnostic. The Positions differ (the blockquote's
        // opening token shifts the nested one by 1), which is the point.
        let nested = try ReplaceStep(from: 4, to: 4, insertText: "X").apply(to: makeDocument()).document
        let flat = try ReplaceStep(from: 3, to: 3, insertText: "X")
            .apply(to: Document(.doc([.paragraph([.text("ab")]), .paragraph([.text("cd")])]))).document
        XCTAssertEqual(nested.root.content[0].content[0].plainText, "aXb")
        XCTAssertEqual(flat.root.content[0].plainText, "aXb")
    }
}
