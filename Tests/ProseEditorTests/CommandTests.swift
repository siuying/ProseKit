import XCTest
@testable import ProseEditor
@testable import ProseModel

final class CommandTests: XCTestCase {
    func testSplitBlockSplitsParagraphAtCaretWithoutInsertingNewline() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        XCTAssertTrue(try Commands.splitBlock().run(in: &state))

        XCTAssertEqual(state.document.root.content.map(\.type), ["paragraph", "paragraph"])
        XCTAssertEqual(state.document.root.content[0].plainText, "he")
        XCTAssertEqual(state.document.root.content[1].plainText, "llo")
        XCTAssertEqual(state.selection, TextSelection(anchor: 6, head: 6))
        XCTAssertFalse(state.document.containsText("\n"))
    }

    func testBackspaceAtBlockStartJoinsWithPreviousBlock() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ])), selection: TextSelection(anchor: 9, head: 9))

        XCTAssertTrue(try Commands.joinBackward().run(in: &state))

        XCTAssertEqual(state.document.root.content.count, 1)
        XCTAssertEqual(state.document.root.content[0].plainText, "helloworld")
        XCTAssertEqual(state.selection, TextSelection(anchor: 7, head: 7))
        XCTAssertFalse(state.document.containsText("\n"))
    }

    func testBackspaceInEmptyBlockRemovesIt() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("")]),
        ])), selection: TextSelection(anchor: 9, head: 9))

        XCTAssertTrue(try Commands.joinBackward().run(in: &state))

        XCTAssertEqual(state.document.root.content.count, 1)
        XCTAssertEqual(state.document.root.content[0].plainText, "hello")
        XCTAssertEqual(state.selection, TextSelection(anchor: 7, head: 7))
    }

    func testToggleHeadingPreservesInlineContent() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        XCTAssertTrue(try Commands.toggleHeading(level: 1).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].type, "heading")
        XCTAssertEqual(state.document.root.content[0].plainText, "hello")

        XCTAssertTrue(try Commands.toggleHeading(level: 1).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].type, "paragraph")
        XCTAssertEqual(state.document.root.content[0].plainText, "hello")
    }
}
