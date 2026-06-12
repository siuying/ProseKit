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
        XCTAssertEqual(state.lastTransaction?.changedRange, 1..<10)
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
        XCTAssertEqual(state.lastTransaction?.changedRange, 1..<14)
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
        XCTAssertEqual(state.lastTransaction?.changedRange, 1..<8)

        XCTAssertTrue(try Commands.toggleHeading(level: 1).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].type, "paragraph")
        XCTAssertEqual(state.document.root.content[0].plainText, "hello")
    }

    func testToggleMarkAddsAndRemovesBasedOnWholeSelection() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 2, head: 7))

        XCTAssertTrue(try Commands.toggleMark(.bold).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].content[0].marks, [.bold])

        XCTAssertTrue(try Commands.toggleMark(.bold).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].content[0].marks, [])
    }

    func testSetLinkWrapsSelectionInLinkMark() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 2, head: 7))

        XCTAssertTrue(try Commands.setLink(href: "https://example.com").run(in: &state))

        let mark = state.document.root.content[0].content[0].marks.first
        XCTAssertEqual(mark?.type, "link")
        XCTAssertEqual(mark?.attrs["href"], .string("https://example.com"))
    }

    func testSetLinkDoesNothingOnCollapsedSelection() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 3, head: 3))

        XCTAssertFalse(try Commands.setLink(href: "https://example.com").run(in: &state))
    }

    func testLinkDetectionRecognisesSoleURL() {
        XCTAssertEqual(LinkDetection.soleURL(in: "https://example.com"), "https://example.com")
        XCTAssertEqual(LinkDetection.soleURL(in: "  https://example.com/a?b=c  "), "https://example.com/a?b=c")
        XCTAssertNil(LinkDetection.soleURL(in: "see https://example.com here"))
        XCTAssertNil(LinkDetection.soleURL(in: "just words"))
        XCTAssertNil(LinkDetection.soleURL(in: ""))
    }

    func testCollapsedToggleMarkAppliesToNextInsertedText() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hi")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        XCTAssertTrue(try Commands.toggleMark(.code).run(in: &state))
        try state.insertText("!")

        XCTAssertEqual(state.document.root.content[0].content[1].text, "!")
        XCTAssertEqual(state.document.root.content[0].content[1].marks, [.code])
    }
}
