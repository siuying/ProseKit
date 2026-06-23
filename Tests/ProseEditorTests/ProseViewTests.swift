#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

@MainActor
final class ProseViewTests: XCTestCase {
    private func makeView(_ document: Document, width: CGFloat = 320) -> ProseView {
        let view = ProseView(document: document)
        view.frame = CGRect(x: 0, y: 0, width: width, height: 480)
        view.layoutIfNeeded()
        return view
    }

    func testSelectionRectsCoverEachLineFragmentWithStartAndEndFlags() throws {
        // Narrow width forces the paragraph to wrap into multiple Line Fragments.
        let view = makeView(
            Document(.doc([.paragraph([.text("the quick brown fox jumps over the lazy dog")])])),
            width: 120
        )
        let anchor = 4
        let head = 30
        let rects = view.selectionRects(for: ProseTextRange(anchor: anchor, head: head))

        XCTAssertGreaterThan(rects.count, 1, "expected one rect per wrapped Line Fragment")
        for rect in rects {
            XCTAssertGreaterThan(rect.rect.width, 0)
            XCTAssertGreaterThan(rect.rect.height, 0)
        }
        XCTAssertTrue(rects.first!.containsStart)
        XCTAssertFalse(rects.first!.containsEnd)
        XCTAssertTrue(rects.last!.containsEnd)
        XCTAssertFalse(rects.last!.containsStart)

        // The first rect starts where the start caret sits, so handles line up.
        let startCaret = view.caretRect(for: ProseTextPosition(anchor))
        XCTAssertEqual(rects.first!.rect.minX, startCaret.minX, accuracy: 0.5)
        let endCaret = view.caretRect(for: ProseTextPosition(head))
        XCTAssertEqual(rects.last!.rect.maxX, endCaret.minX, accuracy: 0.5)
    }

    func testFirstRectForRangeSpansTheRangeOnItsFirstLine() throws {
        let view = makeView(
            Document(.doc([.paragraph([.text("the quick brown fox jumps over the lazy dog")])])),
            width: 120
        )
        let anchor = 4
        let head = 30
        let firstRect = view.firstRect(for: ProseTextRange(anchor: anchor, head: head))

        // It is the first selection rect of the range, not a caret-width sliver.
        let firstSelectionRect = view.selectionRects(for: ProseTextRange(anchor: anchor, head: head)).first!.rect
        XCTAssertEqual(firstRect.minX, firstSelectionRect.minX, accuracy: 0.5)
        XCTAssertEqual(firstRect.maxX, firstSelectionRect.maxX, accuracy: 0.5)
        XCTAssertEqual(firstRect.minY, firstSelectionRect.minY, accuracy: 0.5)
        XCTAssertGreaterThan(firstRect.width, 10, "first rect should span glyphs, not just the caret")
    }

    func testPositionInLayoutDirectionMovesBetweenLinesAndCharacters() throws {
        let view = makeView(
            Document(.doc([.paragraph([.text("the quick brown fox jumps over the lazy dog")])])),
            width: 120
        )
        let start = ProseTextPosition(4)
        let startRect = view.caretRect(for: start)

        // Down lands on the line below; up from there comes back to the first line.
        let below = view.position(from: start, in: .down, offset: 1) as! ProseTextPosition
        let belowRect = view.caretRect(for: below)
        XCTAssertGreaterThan(belowRect.minY, startRect.minY, "down should move to the next Line Fragment")
        XCTAssertEqual(belowRect.minX, startRect.minX, accuracy: 12, "down should preserve x")

        let backUp = view.position(from: below, in: .up, offset: 1) as! ProseTextPosition
        XCTAssertEqual(view.caretRect(for: backUp).minY, startRect.minY, accuracy: 0.5)

        // Left/right stay character-based.
        let right = view.position(from: start, in: .right, offset: 1) as! ProseTextPosition
        XCTAssertEqual(right.position, 5)
        let left = view.position(from: start, in: .left, offset: 1) as! ProseTextPosition
        XCTAssertEqual(left.position, 3)
    }

    func testSettingSelectedTextRangeNotifiesInputDelegate() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let spy = InputDelegateSpy()
        view.inputDelegate = spy

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)

        XCTAssertEqual(spy.events, [.selectionWillChange, .selectionDidChange])
    }

    func testSettingSelectedTextRangeToCurrentSelectionIsANoop() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let spy = InputDelegateSpy()
        var stateChangeCount = 0
        view.inputDelegate = spy
        view.onStateChange = { stateChangeCount += 1 }

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)

        XCTAssertEqual(spy.events, [])
        XCTAssertEqual(stateChangeCount, 0)
    }

    func testBlockFormatCommandPreservesSelectionAndNotifiesInputDelegate() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)
        let spy = InputDelegateSpy()
        view.inputDelegate = spy

        view.setBlockType(headingLevel: 1)

        XCTAssertEqual(view.document.root.content[0].type, "heading")
        XCTAssertEqual(view.selectedTextRange as? ProseTextRange, ProseTextRange(anchor: 2, head: 7))
        XCTAssertEqual(spy.events, [
            .selectionWillChange,
            .textWillChange,
            .textDidChange,
            .selectionDidChange,
        ])
    }

    func testMovingTheSelectionDoesNotRepaintTheCanvas() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        view.layoutIfNeeded()
        // Consume the layout pass's repaint so the flag starts clean.
        view.canvas.layer.displayIfNeeded()
        XCTAssertFalse(view.canvas.layer.needsDisplay(), "precondition: canvas should be clean before the selection change")

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)

        XCTAssertFalse(
            view.canvas.layer.needsDisplay(),
            "selection changes draw no canvas pixels — the system draws the caret/selection — so they must not invalidate the Canvas"
        )
    }

    func testEditableTextInteractionOwnsSelectionUX() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let interaction = view.interactions.compactMap { $0 as? UITextInteraction }.first

        XCTAssertNotNil(interaction, "system selection UX requires a UITextInteraction")
        XCTAssertEqual(interaction?.textInput === view, true)
    }

    func testTaskCheckboxHitTestReturnsTaskItemTextStart() throws {
        let view = makeView(Document(.doc([
            .taskList([.taskItem(checked: false, [.paragraph([.text("todo")])])]),
        ])))
        let item = view.layoutBox!.children[0].children[0]
        let paragraph = item.children[0]
        let lineHeight = paragraph.lineFragments.first!.frame.height
        let point = CGPoint(x: item.frame.minX + 12, y: paragraph.frame.minY + lineHeight / 2)

        XCTAssertEqual(view.taskCheckboxPosition(at: point), 4)
    }

    // `gesture.location(in:)` on a UIScrollView is already in content space
    // (bounds.origin == contentOffset), so the hit-test must use it directly —
    // the same convention as closestPosition(to:). When the keyboard scrolls the
    // editor, a stray contentOffset add would push the hit rect off the tap.
    func testTaskCheckboxHitTestHoldsWhenScrolled() throws {
        let view = makeView(Document(.doc([
            .paragraph([.text(String(repeating: "filler ", count: 60))]),
            .taskList([.taskItem(checked: false, [.paragraph([.text("todo")])])]),
        ])))
        view.contentOffset.y = 200
        let item = view.layoutBox!.children[1].children[0]
        let paragraph = item.children[0]
        let lineHeight = paragraph.lineFragments.first!.frame.height
        let point = CGPoint(x: item.frame.minX + 12, y: paragraph.frame.minY + lineHeight / 2)

        XCTAssertEqual(view.taskCheckboxPosition(at: point), item.children[0].positionRange.lowerBound + 1)
    }

    func testTappingCheckboxTogglesCheckedAttrBothWays() throws {
        let view = makeView(Document(.doc([
            .taskList([.taskItem(checked: false, [.paragraph([.text("todo")])])]),
        ])))
        let item = view.layoutBox!.children[0].children[0]
        let paragraph = item.children[0]
        let lineHeight = paragraph.lineFragments.first!.frame.height
        let point = CGPoint(x: item.frame.minX + 12, y: paragraph.frame.minY + lineHeight / 2)

        func checked() -> Bool {
            view.layoutBox!.children[0].children[0].node.attrs["checked"]?.boolValue ?? false
        }

        XCTAssertFalse(checked())
        XCTAssertTrue(view.toggleTaskCheckbox(at: point))
        XCTAssertTrue(checked())
        XCTAssertTrue(view.toggleTaskCheckbox(at: point))
        XCTAssertFalse(checked())
    }

    func testTapMissingAnyCheckboxLeavesDocumentUnchanged() throws {
        let view = makeView(Document(.doc([
            .taskList([.taskItem(checked: false, [.paragraph([.text("todo")])])]),
        ])))
        // Far to the right of the checkbox, over the text — not a checkbox hit.
        XCTAssertFalse(view.toggleTaskCheckbox(at: CGPoint(x: 200, y: 12)))
    }

    func testCopyPutsSelectedPlainTextOnPasteboard() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard

        // Collapsed selection: nothing to copy.
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))

        // "hello" is positions 2..<7.
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        view.copy(nil)

        XCTAssertEqual(pasteboard.string, "hello")
    }

    func testCutCopiesSelectionAndRemovesItFromTheDocument() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil))

        // "hello " is positions 2..<8.
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 8)
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil))
        view.cut(nil)

        XCTAssertEqual(pasteboard.string, "hello ")
        XCTAssertEqual(view.document.plainText, "world")
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.anchor, 2, "caret collapses to where the cut text was")
        XCTAssertEqual(selection.head, 2)
    }

    // Cut collapses the selection programmatically, so — like paste — the input
    // delegate must be told the selection changed. Otherwise the system
    // selection-display chrome keeps drawing the old highlight over text that
    // is no longer there.
    func testCutNotifiesInputDelegateSoTheSelectionHighlightClears() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard

        // Select "hello " (positions 2..<8).
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 8)
        let spy = InputDelegateSpy()
        view.inputDelegate = spy

        view.cut(nil)

        XCTAssertEqual(spy.events.first, .selectionWillChange,
                       "cut opens with selectionWillChange so the system tracks the collapse")
        XCTAssertEqual(spy.events.last, .selectionDidChange,
                       "cut closes with selectionDidChange so the stale highlight is cleared")
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertTrue(selection.isEmpty, "the selection collapses, leaving no range to highlight")
    }

    func testPasteReplacesSelectionWithPasteboardText() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard

        pasteboard.items = []
        XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))

        pasteboard.string = "brave new"
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))

        // Replace "hello" (positions 2..<7).
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)
        view.paste(nil)

        XCTAssertEqual(view.document.plainText, "brave new world")
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.anchor, 2 + "brave new".count, "caret lands after the pasted text")
        XCTAssertTrue(selection.isEmpty)
    }

    // Paste moves the caret to the end of the inserted run programmatically, so
    // the input delegate must be told the selection changed — otherwise the
    // system caret chrome lags behind state.selection and stays where it was.
    func testPasteNotifiesInputDelegateOfSelectionChange() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard
        pasteboard.string = "brave new"

        // Caret before "world" (position 8) — a collapsed insertion, not a replace.
        view.selectedTextRange = ProseTextRange(anchor: 8, head: 8)
        let spy = InputDelegateSpy()
        view.inputDelegate = spy

        view.paste(nil)

        XCTAssertEqual(spy.events.first, .selectionWillChange,
                       "paste opens with selectionWillChange so the system tracks the caret move")
        XCTAssertEqual(spy.events.last, .selectionDidChange,
                       "paste closes with selectionDidChange so the caret chrome catches up to the new caret")
    }

    func testPastingURLOntoSelectionLinksItInsteadOfReplacing() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard
        pasteboard.string = "https://example.com"

        // Select "hello" (positions 2..<7) and paste a URL.
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 7)
        view.paste(nil)

        XCTAssertEqual(view.document.plainText, "hello world", "the selected text is kept, not replaced")
        let mark = view.document.root.content[0].content.first?.marks.first
        XCTAssertEqual(mark?.type, "link")
        XCTAssertEqual(mark?.attrs["href"], .string("https://example.com"))
    }

    func testPastingMultiLineTextSplitsBlocks() throws {
        let view = makeView(Document(.doc([.paragraph([.text("ad")])])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard
        pasteboard.string = "b\nc"

        // Caret between "a" and "d" (position 3).
        view.selectedTextRange = ProseTextRange(anchor: 3, head: 3)
        view.paste(nil)

        // Each \n behaves like typing Return: the paragraph splits.
        let blocks = view.document.root.content
        XCTAssertEqual(blocks.map(\.plainText), ["ab", "cd"])
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(view.text(in: ProseTextRange(anchor: selection.head - 1, head: selection.head)), "c",
                       "caret lands after the last pasted segment")
    }

    func testSelectChoosesWordAtCaretAndSelectAllSpansTheDocument() throws {
        let view = makeView(Document(.doc([
            .paragraph([.text("hello world")]),
            .paragraph([.text("tail")]),
        ])))

        // Caret inside "world" ("hello world" text spans 2..<13).
        view.selectedTextRange = ProseTextRange(anchor: 10, head: 10)
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.select(_:)), withSender: nil))
        view.select(nil)
        XCTAssertEqual(view.text(in: view.selectedTextRange!), "world")

        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.selectAll(_:)), withSender: nil))
        view.selectAll(nil)
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(min(selection.anchor, selection.head), 2, "starts at the document's first text position")
        XCTAssertEqual(max(selection.anchor, selection.head), view.document.endTextPosition)
    }

    func testCopyAfterSelectAllJoinsBlocksWithNewlines() throws {
        let view = makeView(Document(.doc([
            .paragraph([.text("hello world")]),
            .paragraph([.text("tail")]),
        ])))
        let pasteboard = UIPasteboard.withUniqueName()
        view.pasteboard = pasteboard

        view.selectAll(nil)
        view.copy(nil)

        XCTAssertEqual(pasteboard.string, "hello world\ntail")
    }

    func testBecomingFirstResponderActivatesSystemSelectionDisplay() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        window.addSubview(view)
        window.makeKeyAndVisible()

        XCTAssertTrue(view.becomeFirstResponder())

        // The system, not ProseView, draws the caret and handles.
        let display = view.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first
        XCTAssertNotNil(display, "UITextInteraction should install the system selection display")
        XCTAssertEqual(display?.isActivated, true, "caret must show on programmatic focus, like UITextView")
        XCTAssertNotNil(display?.cursorView, "system caret view should exist")

        XCTAssertTrue(view.resignFirstResponder())
        XCTAssertEqual(display?.isActivated, false, "caret hides when focus is lost")
    }

    func testTokenizerSelectsWholeWordInLaterBlocks() throws {
        // Double-tap word selection goes through the system tokenizer, which
        // mixes text(in:) string offsets with position(from:offset:) moves.
        // A block boundary is 2 positions but reads as one "\n", so words in
        // later blocks used to come back short by one character per
        // preceding boundary.
        let view = makeView(Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([.text("world")]),
            .paragraph([.text("Testing")]),
        ])))

        // Caret inside "Testing" ("Testing" text spans 16..<23).
        let caret = ProseTextPosition(19)
        let word = try XCTUnwrap(view.tokenizer.rangeEnclosingPosition(caret, with: .word, inDirection: .storage(.backward)))
        XCTAssertEqual(view.text(in: word), "Testing")

        view.selectedTextRange = ProseTextRange(anchor: 19, head: 19)
        view.select(nil)
        XCTAssertEqual(view.text(in: view.selectedTextRange!), "Testing")
    }

    // Option+Arrow word movement, matching UITextView. "hello world" spans
    // positions 2..<13: 'h'=2 … 'o'=6, ' '=7, 'w'=8 … 'd'=12, end=13.
    func testOptionArrowMovesCaretByWord() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))

        // From the start of "hello", Option+Right lands at the end of "hello".
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        view.moveCaretByWord(.right, extending: false)
        var selection = view.selectedTextRange as! ProseTextRange
        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.head, 7, "Option+Right stops at the end of the current word")

        // Again, skipping the space, to the end of "world".
        view.moveCaretByWord(.right, extending: false)
        selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.head, 13, "Option+Right crosses the space to the next word end")

        // Option+Left walks back to the start of "world", then "hello".
        view.moveCaretByWord(.left, extending: false)
        selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.head, 8, "Option+Left stops at the start of the word")
        view.moveCaretByWord(.left, extending: false)
        selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.head, 2, "Option+Left crosses the space to the previous word start")
    }

    // Option+Shift+Arrow extends the selection by whole words, anchoring where
    // it started.
    func testOptionShiftArrowExtendsSelectionByWord() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        view.moveCaretByWord(.right, extending: true)
        let selection = view.selectedTextRange as! ProseTextRange
        XCTAssertEqual(selection.anchor, 2, "the anchor stays where the selection began")
        XCTAssertEqual(selection.head, 7, "the head extends to the word boundary")
        XCTAssertEqual(view.text(in: selection), "hello")
    }

    func testOffsetArithmeticMatchesTextInAcrossBlockBoundaries() throws {
        // UITextInput contract: offset(from:to:) must equal the character
        // count of text(in:) for the same range, and position(from:offset:)
        // must be its inverse.
        let view = makeView(Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([.text("world")]),
            .paragraph([.text("Testing")]),
        ])))

        let begin = view.beginningOfDocument
        let end = view.endOfDocument
        let text = try XCTUnwrap(view.text(in: ProseTextRange(anchor: 2, head: view.document.endTextPosition)))
        XCTAssertEqual(text, "Hello\nworld\nTesting")
        XCTAssertEqual(view.offset(from: begin, to: end), text.count)

        // Advancing by the character offset of "Testing" in the joined text
        // lands on its first document position (16).
        let testingStart = view.position(from: begin, offset: 12) as! ProseTextPosition
        XCTAssertEqual(testingStart.position, 16)
        XCTAssertEqual(view.offset(from: begin, to: testingStart), 12)

        // Round-trip from a position inside "world" (9..<14).
        let insideWorld = ProseTextPosition(11)
        let offset = view.offset(from: begin, to: insideWorld)
        XCTAssertEqual(offset, 8, "\"Hello\\n\" is 6 chars, plus 2 into \"world\"")
        XCTAssertEqual((view.position(from: begin, offset: offset) as! ProseTextPosition).position, 11)
    }

    func testDeleteBackwardAtDocumentStartDoesNothing() {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ]))
        let view = makeView(document)
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)

        // Regression: this asserted (crashing debug builds) instead of
        // being the inert Backspace UITextView ships.
        view.deleteBackward()

        XCTAssertEqual(view.document, document)
        XCTAssertEqual((view.selectedTextRange as? ProseTextRange)?.head, 2)
    }

    func testDeleteBackwardOverCrossBlockSelectionDeletesAndJoins() {
        // Deleting a selection that spans blocks removes the selected text
        // and merges the boundary blocks (ProseMirror replace semantics).
        let view = makeView(Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ])))
        view.selectedTextRange = ProseTextRange(anchor: 4, head: 11)

        view.deleteBackward()

        XCTAssertEqual(view.document.root.content.count, 1)
        XCTAssertEqual(view.document.plainText, "herld")
        XCTAssertEqual((view.selectedTextRange as? ProseTextRange)?.head, 4)
    }

    func testReplacingTheBlockBoundaryNewlineJoinsBlocks() {
        // The iOS keyboard backspaces at a block start by replacing the
        // boundary "\n" in character space via replace(_:withText:) — a path
        // deleteBackward's join command never sees. It must join the blocks.
        let view = makeView(Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ])))

        view.replace(ProseTextRange(anchor: 7, head: 9), withText: "")

        XCTAssertEqual(view.document.root.content.count, 1)
        XCTAssertEqual(view.document.plainText, "helloworld")
        XCTAssertEqual((view.selectedTextRange as? ProseTextRange)?.head, 7)
    }
}

@MainActor
@MainActor
extension ProseViewTests {
    // MARK: - Live block input rules (Phase 1)

    func testTypingHashSpaceConvertsToHeadingInIOSView() {
        let view = makeView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.selectedTextRange = ProseTextRange(anchor: start, head: start)

        view.insertText("# ")

        XCTAssertEqual(view.document.root.content[0].type, "heading")
        XCTAssertEqual(view.document.root.content[0].attrs["level"], .int(1))
        XCTAssertEqual(view.document.root.content[0].plainText, "")
    }

    func testTypingGtSpaceWrapsInBlockquoteInIOSView() {
        let view = makeView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.selectedTextRange = ProseTextRange(anchor: start, head: start)

        view.insertText("> ")

        XCTAssertEqual(view.document.root.content[0].type, "blockquote")
    }

    // MARK: - Live inline mark rules (Phase 3)

    private func emptyParaIOSView() -> ProseView {
        let view = makeView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.selectedTextRange = ProseTextRange(anchor: start, head: start)
        return view
    }

    private func typeLive(_ text: String, into view: ProseView) {
        for character in text { view.insertText(String(character)) }
    }

    func testTypingStarItalicLeavesTrailingSpacePlainInIOSView() {
        let view = emptyParaIOSView()

        typeLive("*Italic* ", into: view)

        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["Italic", " "])
        XCTAssertEqual(runs.map(\.marks), [[.italic], []])
    }

    func testTypingBoldInIOSView() {
        let view = emptyParaIOSView()
        typeLive("**Bold**", into: view)
        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["Bold"])
        XCTAssertEqual(runs.map(\.marks), [[.bold]])
    }

    func testTypingCodePreservesPrecedingCharInIOSView() {
        let view = emptyParaIOSView()
        typeLive("a`Code`", into: view)
        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["a", "Code"])
        XCTAssertEqual(runs.map(\.marks), [[], [.code]])
    }

    // MARK: - Immediate Backspace revert (Phase 4)

    func testBackspaceAfterBlockShortcutRestoresLiteralInIOSView() {
        let view = emptyParaIOSView()
        view.insertText("# ")
        XCTAssertEqual(view.document.root.content[0].type, "heading")

        view.deleteBackward()

        XCTAssertEqual(view.document.root.content[0].type, "paragraph")
        XCTAssertEqual(view.document.root.content[0].plainText, "# ")
    }

    func testBackspaceAfterInlineShortcutRestoresLiteralInIOSView() {
        let view = emptyParaIOSView()
        typeLive("*Italic*", into: view)
        XCTAssertEqual(view.document.root.content[0].content.first?.marks, [.italic])

        view.deleteBackward()

        XCTAssertEqual(view.document.root.content[0].plainText, "*Italic*")
        XCTAssertEqual(view.document.root.content[0].content.map(\.marks), [[]])
    }
}

private final class InputDelegateSpy: NSObject, UITextInputDelegate {
    enum Event: Equatable {
        case selectionWillChange, selectionDidChange, textWillChange, textDidChange
    }

    private(set) var events: [Event] = []

    func selectionWillChange(_ textInput: UITextInput?) { events.append(.selectionWillChange) }
    func selectionDidChange(_ textInput: UITextInput?) { events.append(.selectionDidChange) }
    func textWillChange(_ textInput: UITextInput?) { events.append(.textWillChange) }
    func textDidChange(_ textInput: UITextInput?) { events.append(.textDidChange) }
    @available(iOS 18.4, *)
    func conversationContext(_ context: UIConversationContext?, didChange textInput: UITextInput?) {}
}
#endif
