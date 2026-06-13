import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Slice 03 wiring: the `> ` input rule wraps a paragraph in a blockquote, and
/// Backspace at the first quoted block lifts it out (via the command the View
/// runs before plain deleteBackward).
final class BlockquoteCommandTests: XCTestCase {
    func testGreaterThanSpaceWrapsParagraphInBlockquote() throws {
        var s = EditorState(
            document: Document(.doc([.paragraph([.text("> ")])])),
            selection: TextSelection(anchor: 4, head: 4)
        )
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "blockquote")
        XCTAssertEqual(s.document.root.content[0].content.map(\.plainText), [""], "trigger consumed; empty quoted paragraph")
        XCTAssertTrue(s.document.canJoinBackward(at: s.selection.head) == false, "caret is at the first quoted block")
    }

    func testWrapInBlockquoteCommandKeepsText() throws {
        var s = EditorState(
            document: Document(.doc([.paragraph([.text("hello")])])),
            selection: TextSelection(anchor: 4, head: 4)
        )
        XCTAssertTrue(try Commands.wrapInBlockquote().run(in: &s))
        XCTAssertEqual(s.document.root.content[0].type, "blockquote")
        XCTAssertEqual(s.document.root.content[0].content[0].plainText, "hello")
    }

    func testLiftCommandUnwrapsFirstQuotedBlock() throws {
        // doc > [ blockquote > [ p("a"), p("b") ], p("c") ], caret at start of p("a") (pos 3).
        var s = EditorState(
            document: Document(.doc([
                .blockquote([.paragraph([.text("a")]), .paragraph([.text("b")])]),
                .paragraph([.text("c")]),
            ])),
            selection: TextSelection(anchor: 3, head: 3)
        )
        XCTAssertTrue(try Commands.liftOutOfContainer().run(in: &s))
        XCTAssertEqual(s.document.root.content.map(\.type), ["paragraph", "blockquote", "paragraph"])
        XCTAssertEqual(s.document.root.content[0].plainText, "a")
        XCTAssertEqual(s.document.root.content[1].content.map(\.plainText), ["b"])
    }

    func testLiftCommandDoesNotFireForASecondQuotedBlock() throws {
        var s = EditorState(
            document: Document(.doc([
                .blockquote([.paragraph([.text("a")]), .paragraph([.text("b")])]),
            ])),
            selection: TextSelection(anchor: 7, head: 7) // start of p("b") — has a previous sibling
        )
        XCTAssertFalse(try Commands.liftOutOfContainer().run(in: &s), "a non-first child joins, not lifts")
    }

    func testLiftCommandDoesNotFireAtTopLevel() throws {
        var s = EditorState(
            document: Document(.doc([.paragraph([.text("a")])])),
            selection: TextSelection(anchor: 2, head: 2)
        )
        XCTAssertFalse(try Commands.liftOutOfContainer().run(in: &s))
    }
}
