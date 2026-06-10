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

    func testEditableTextInteractionOwnsSelectionUX() throws {
        let view = makeView(Document(.doc([.paragraph([.text("hello world")])])))
        let interaction = view.interactions.compactMap { $0 as? UITextInteraction }.first

        XCTAssertNotNil(interaction, "system selection UX requires a UITextInteraction")
        XCTAssertEqual(interaction?.textInput === view, true)
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
}

@MainActor
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
