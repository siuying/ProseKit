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

    func testSplitBlockInsideBulletListCreatesSiblingListItem() throws {
        var state = EditorState(document: Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("ab")])]),
                .listItem([.paragraph([.text("cd")])]),
            ]),
        ])), selection: TextSelection(anchor: 5, head: 5))

        XCTAssertTrue(try Commands.splitBlock().run(in: &state))

        let list = state.document.root.content[0]
        XCTAssertEqual(list.content.map(\.plainText), ["a", "b", "cd"])
        XCTAssertEqual(state.selection, TextSelection(anchor: 9, head: 9))
    }

    func testSplitBlockOnEmptyListItemExitsTheList() throws {
        var state = EditorState(document: Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("ab")])]),
                .listItem([.paragraph([])]),
                .listItem([.paragraph([.text("cd")])]),
            ]),
        ])), selection: TextSelection(anchor: 10, head: 10))

        XCTAssertTrue(try Commands.splitBlock().run(in: &state))

        XCTAssertEqual(state.document.root.content.map(\.type), ["bulletList", "paragraph", "bulletList"])
        XCTAssertEqual(state.document.root.content[0].plainText, "ab")
        XCTAssertEqual(state.document.root.content[1].plainText, "")
        XCTAssertEqual(state.document.root.content[2].plainText, "cd")
        XCTAssertEqual(state.selection, TextSelection(anchor: 8, head: 8))
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

    func testBackspaceAtListItemStartJoinsWithPreviousItem() throws {
        var state = EditorState(document: Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("ab")])]),
                .listItem([.paragraph([.text("cd")])]),
            ]),
        ])), selection: TextSelection(anchor: 10, head: 10))

        XCTAssertTrue(try Commands.joinBackward().run(in: &state))

        let list = state.document.root.content[0]
        XCTAssertEqual(list.content.count, 1)
        XCTAssertEqual(list.content[0].plainText, "abcd")
        XCTAssertEqual(state.selection, TextSelection(anchor: 6, head: 6))
    }

    func testJoinBackwardPreservesMarksOfBothBlocks() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("a", marks: [.bold])]),
            .paragraph([.text("b", marks: [.italic])]),
        ])), selection: TextSelection(anchor: 5, head: 5))

        XCTAssertTrue(try Commands.joinBackward().run(in: &state))

        let runs = state.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["a", "b"])
        XCTAssertEqual(runs[0].marks, [.bold])
        XCTAssertEqual(runs[1].marks, [.italic])
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

    func testSetBlockTypeChangesHeadingLevelWithoutToggling() throws {
        var state = EditorState(document: Document(.doc([
            .heading(level: 1, [.text("hi")]),
        ])), selection: TextSelection(anchor: 4, head: 4))

        XCTAssertTrue(try Commands.setBlockType(headingLevel: 3).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].type, "heading")
        XCTAssertEqual(state.document.root.content[0].attrs["level"], .int(3),
                       "a different level changes the level rather than reverting to paragraph")

        XCTAssertTrue(try Commands.setBlockType(headingLevel: nil).run(in: &state))
        XCTAssertEqual(state.document.root.content[0].type, "paragraph")
    }

    func testSetTextAlignSetsAndClearsBlockAttr() throws {
        var state = EditorState(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])), selection: TextSelection(anchor: 3, head: 3))

        XCTAssertTrue(try Commands.setTextAlign("center").run(in: &state))
        XCTAssertEqual(state.document.root.content[0].attrs["textAlign"], .string("center"))

        XCTAssertTrue(try Commands.setTextAlign(nil).run(in: &state))
        XCTAssertNil(state.document.root.content[0].attrs["textAlign"], "left/nil clears the redundant attr")
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
