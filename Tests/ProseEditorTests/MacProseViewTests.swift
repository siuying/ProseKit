#if canImport(AppKit)
import AppKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

@MainActor
final class MacProseViewTests: XCTestCase {
    func testMacProseViewHostsAFlippedContentSizedNonLayerBackedCanvas() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
            .paragraph([.text("scrollable content")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()

        let canvas = try XCTUnwrap(view.documentView)
        XCTAssertTrue(canvas.isFlipped)
        XCTAssertFalse(canvas.wantsLayer)
        XCTAssertEqual(canvas.frame.width, 320)
        XCTAssertGreaterThan(canvas.frame.height, 0)
        XCTAssertTrue(view.canvasView.superview === canvas)
        XCTAssertTrue(view.selectionLayer.superview === canvas)
        XCTAssertTrue(canvas.subviews.first === view.canvasView)
        XCTAssertTrue(canvas.subviews.last === view.selectionLayer)
        XCTAssertTrue(view.hasVerticalScroller)
    }

    func testClickingInMacViewPlacesACaretThroughSharedGeometry() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let click = CGPoint(x: 74, y: 18)
        let expectedPosition = view.core.closestPosition(to: click)

        view.placeCaret(atContentPoint: click)

        XCTAssertEqual(view.core.selection, TextSelection(anchor: expectedPosition, head: expectedPosition))
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
        XCTAssertEqual(view.selectionLayer.caretRect, view.core.caretRect(for: expectedPosition))
    }

    func testMacCaretVisibilityTracksFirstResponderState() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()

        view.placeCaret(atContentPoint: CGPoint(x: 42, y: 18))
        XCTAssertTrue(view.selectionLayer.drawsCaret)
        XCTAssertNotNil(view.selectionLayer.blinkTimer)

        XCTAssertTrue(view.resignFirstResponder())
        XCTAssertFalse(view.selectionLayer.drawsCaret)
        XCTAssertNil(view.selectionLayer.blinkTimer)

        XCTAssertTrue(view.becomeFirstResponder())
        XCTAssertTrue(view.selectionLayer.drawsCaret)
        XCTAssertNotNil(view.selectionLayer.blinkTimer)
    }

    func testMacTextInputInsertsTextAndAdvancesCaret() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))

        view.insertText(" mac", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(view.document.plainText, "hello mac")
        XCTAssertEqual(view.core.selection, TextSelection(anchor: end + 4, head: end + 4))
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacDoCommandRoutesDeleteAndReturnThroughEditorCommands() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))

        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(view.document.plainText, "hell")
        let afterDelete = view.core.selection.head

        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(view.document.blockCount, 2)
        XCTAssertGreaterThan(view.core.selection.head, afterDelete)
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacMarkedTextCommitsThroughTextInputClient() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("cafe")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))

        view.setMarkedText("e", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.document.plainText, "cafee")

        view.insertText("é", replacementRange: view.markedRange())

        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.document.plainText, "cafeé")
    }

    func testMacTextInputEditsCanUndoAndRedoThroughCoreHistory() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertTrue(view.core.undo())
        XCTAssertEqual(view.document.plainText, "hello")

        XCTAssertTrue(view.core.redo())
        XCTAssertEqual(view.document.plainText, "hello!")
    }

    func testMacMouseDragSelectsRangeThroughSharedGeometry() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let start = CGPoint(x: 40, y: 18)
        let end = CGPoint(x: 92, y: 18)
        let anchor = view.core.closestPosition(to: start)
        let head = view.core.closestPosition(to: end)

        view.beginSelection(atContentPoint: start)
        view.extendSelection(toContentPoint: end)

        XCTAssertEqual(view.core.selection, TextSelection(anchor: anchor, head: head))
        XCTAssertEqual(view.canvasView.selectionRects, view.core.selectionRects(for: view.core.selection))
        XCTAssertTrue(view.canvasView.drawsSelectionHighlight)
        XCTAssertFalse(view.selectionLayer.drawsCaret)
    }

    func testMacDoubleAndTripleClickSelectWordAndParagraph() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
            .paragraph([.text("next")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let firstTextStart = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        let wordPoint = view.core.caretRect(for: firstTextStart + 1).offsetBy(dx: 2, dy: 0).origin

        view.selectWord(atContentPoint: wordPoint)
        XCTAssertEqual(
            try view.document.text(from: view.core.selection.anchor, to: view.core.selection.head),
            "hello"
        )

        view.selectParagraph(atContentPoint: wordPoint)
        XCTAssertEqual(view.core.selection, TextSelection(anchor: firstTextStart, head: firstTextStart + 9))
    }

    func testMacSelectionHighlightUsesActiveAndInactiveWindowColors() throws {
        let canvas = MacCanvasView()
        canvas.selectionRects = [CGRect(x: 1, y: 2, width: 3, height: 4)]

        canvas.setWindowIsKey(true)
        let active = canvas.selectionHighlightColor
        canvas.setWindowIsKey(false)

        XCTAssertTrue(canvas.drawsSelectionHighlight)
        XCTAssertNotEqual(active, canvas.selectionHighlightColor)
    }

    func testMacSelectionHighlightDrawsBehindTextOnTheCanvas() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(view.documentView)

        view.beginSelection(atContentPoint: CGPoint(x: 40, y: 18))
        view.extendSelection(toContentPoint: CGPoint(x: 92, y: 18))

        // The highlight must be painted by the canvas, beneath the glyphs, so the
        // selected text stays legible instead of being covered by an opaque fill.
        XCTAssertEqual(view.canvasView.selectionRects, view.core.selectionRects(for: view.core.selection))
        XCTAssertTrue(view.canvasView.drawsSelectionHighlight)
        XCTAssertTrue(canvas.subviews.first === view.canvasView)
        XCTAssertTrue(canvas.subviews.last === view.selectionLayer)
    }

    func testMacDoCommandMovesCaretAndExtendsSelection() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: start + 2, head: start + 2))

        view.doCommand(by: #selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 3, head: start + 3))

        view.doCommand(by: #selector(NSResponder.moveLeftAndModifySelection(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 3, head: start + 2))
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacDoCommandMovesByWordAndToParagraphEdges() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: start, head: start))

        view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 5, head: start + 5))

        view.doCommand(by: #selector(NSResponder.moveWordRightAndModifySelection(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 5, head: start + 11))

        view.doCommand(by: #selector(NSResponder.moveToBeginningOfParagraph(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start, head: start))

        view.doCommand(by: #selector(NSResponder.moveToEndOfParagraph(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 11, head: start + 11))
    }

    func testMacDoCommandDeletesWords() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: start + 11, head: start + 11))

        view.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
        XCTAssertEqual(view.document.plainText, "hello ")

        view.core.setSelection(TextSelection(anchor: start, head: start))
        view.doCommand(by: #selector(NSResponder.deleteWordForward(_:)))
        XCTAssertEqual(view.document.plainText, " ")
    }

    func testMacDoCommandRunsSharedTabBindingsForListItems() throws {
        let view = ProseView(document: Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("ab")])]),
                .listItem([.paragraph([.text("cd")])]),
            ]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        view.core.setSelection(TextSelection(anchor: 10, head: 10))

        view.doCommand(by: #selector(NSResponder.insertTab(_:)))

        var firstItem = view.document.root.content[0].content[0]
        XCTAssertEqual(firstItem.content.map(\.type), ["paragraph", "bulletList"])

        view.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        firstItem = view.document.root.content[0].content[0]
        XCTAssertEqual(firstItem.content.map(\.type), ["paragraph"])
        XCTAssertEqual(view.document.root.content[0].content.map(\.plainText), ["ab", "cd"])
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacCopyPutsSelectedPlainTextOnPasteboard() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        let pasteboard = TestPasteboard()
        view.pasteboard = pasteboard
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))

        view.core.setSelection(TextSelection(anchor: start, head: start + 5))
        view.copy(nil)

        XCTAssertEqual(pasteboard.string, "hello")
    }

    func testMacCutCopiesSelectionAndRemovesItFromTheDocument() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        let pasteboard = TestPasteboard()
        view.pasteboard = pasteboard
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))

        view.core.setSelection(TextSelection(anchor: start, head: start + 6))
        view.cut(nil)

        XCTAssertEqual(pasteboard.string, "hello ")
        XCTAssertEqual(view.document.plainText, "world")
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start, head: start))
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacPasteReplacesSelectionWithPasteboardText() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        let pasteboard = TestPasteboard()
        pasteboard.string = "brave new"
        view.pasteboard = pasteboard
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))

        view.core.setSelection(TextSelection(anchor: start, head: start + 5))
        view.paste(nil)

        XCTAssertEqual(view.document.plainText, "brave new world")
        XCTAssertEqual(view.core.selection, TextSelection(anchor: start + 9, head: start + 9))
        XCTAssertEqual(view.selectionLayer.selection, view.core.selection)
    }

    func testMacClipboardActionsValidateThroughResponderItems() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        let pasteboard = TestPasteboard()
        view.pasteboard = pasteboard
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: start, head: start))

        XCTAssertFalse(view.validateUserInterfaceItem(TestValidatedItem(action: #selector(ProseView.copy(_:)))))
        XCTAssertFalse(view.validateUserInterfaceItem(TestValidatedItem(action: #selector(ProseView.cut(_:)))))
        XCTAssertFalse(view.validateMenuItem(NSMenuItem(title: "Paste", action: #selector(ProseView.paste(_:)), keyEquivalent: "")))

        pasteboard.string = "mac"
        XCTAssertTrue(view.validateUserInterfaceItem(TestValidatedItem(action: #selector(ProseView.paste(_:)))))

        view.core.setSelection(TextSelection(anchor: start, head: start + 5))
        XCTAssertTrue(view.validateMenuItem(NSMenuItem(title: "Copy", action: #selector(ProseView.copy(_:)), keyEquivalent: "")))
        XCTAssertTrue(view.validateUserInterfaceItem(TestValidatedItem(action: #selector(ProseView.cut(_:)))))
    }

    func testMacFormatMenuUsesSharedBindingsAndReflectsActiveMarks() throws {
        let menu = MacProseFormatMenu.makeMenu()
        let boldItem = try XCTUnwrap(menu.item(withTitle: "Bold"))
        let italicItem = try XCTUnwrap(menu.item(withTitle: "Italic"))

        XCTAssertEqual(boldItem.keyEquivalent, "b")
        XCTAssertTrue(boldItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertEqual(boldItem.action, #selector(ProseView.toggleBoldface(_:)))
        XCTAssertEqual(italicItem.keyEquivalent, "i")
        XCTAssertTrue(italicItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertEqual(italicItem.action, #selector(ProseView.toggleItalics(_:)))

        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello world")]),
        ])))
        let start = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: start, head: start + 5))

        XCTAssertTrue(view.validateMenuItem(boldItem))
        XCTAssertEqual(boldItem.state, .off)

        view.toggleBoldface(nil)

        XCTAssertEqual(view.document.root.content[0].content[0].marks, [.bold])
        XCTAssertTrue(view.validateMenuItem(boldItem))
        XCTAssertEqual(boldItem.state, .on)
    }

    func testMacEditMenuActionsUseCoreHistoryAndSelectionQueries() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))
        let undoItem = NSMenuItem(title: "Undo", action: #selector(ProseView.undo(_:)), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(ProseView.redo(_:)), keyEquivalent: "z")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(ProseView.selectAll(_:)), keyEquivalent: "a")

        XCTAssertFalse(view.validateMenuItem(undoItem))
        view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertTrue(view.validateMenuItem(undoItem))
        view.undo(nil)
        XCTAssertEqual(view.document.plainText, "hello")

        XCTAssertTrue(view.validateMenuItem(redoItem))
        view.redo(nil)
        XCTAssertEqual(view.document.plainText, "hello!")

        XCTAssertTrue(view.validateMenuItem(selectAllItem))
        view.selectAll(nil)
        XCTAssertEqual(view.core.selection, TextSelection(anchor: view.document.startTextPosition, head: view.document.endTextPosition))
    }

    func testMacDoubleClickSelectsWordWithoutCrossingBlocks() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let firstTextStart = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        let point = view.core.caretRect(for: firstTextStart + 1).offsetBy(dx: 2, dy: 0).origin

        view.selectWord(atContentPoint: point)

        XCTAssertEqual(
            try view.document.text(from: view.core.selection.anchor, to: view.core.selection.head),
            "hello"
        )
    }

    func testMacWordMotionTreatsBlockBoundaryAsAWordBreak() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([.text("world")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let firstStart = try XCTUnwrap(view.document.position(ofTextInBlockAt: 0))
        view.core.setSelection(TextSelection(anchor: firstStart, head: firstStart))

        view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: firstStart + 5, head: firstStart + 5))

        view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        let secondStart = try XCTUnwrap(view.document.position(ofTextInBlockAt: 1))
        XCTAssertEqual(view.core.selection, TextSelection(anchor: secondStart + 5, head: secondStart + 5))
    }

    func testMacClearingMarkedTextRemovesProvisionalCharacters() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("cafe")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        let end = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: end, head: end))

        view.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.document.plainText, "cafen")

        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.document.plainText, "cafe")
    }

    func testMacAttributedSubstringReturnsNilForNotFoundRange() throws {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()

        XCTAssertNil(view.attributedSubstring(forProposedRange: NSRange(location: NSNotFound, length: 0), actualRange: nil))
    }

    func testMacEditMenuFactoryWiresStandardActions() throws {
        let menu = MacProseEditMenu.makeMenu()

        let undo = try XCTUnwrap(menu.item(withTitle: "Undo"))
        XCTAssertEqual(undo.action, #selector(ProseView.undo(_:)))
        XCTAssertEqual(undo.keyEquivalent, "z")
        XCTAssertTrue(undo.keyEquivalentModifierMask.contains(.command))

        let redo = try XCTUnwrap(menu.item(withTitle: "Redo"))
        XCTAssertTrue(redo.keyEquivalentModifierMask.contains(.shift))

        XCTAssertEqual(try XCTUnwrap(menu.item(withTitle: "Paste")).action, #selector(ProseView.paste(_:)))
        XCTAssertEqual(try XCTUnwrap(menu.item(withTitle: "Select All")).action, #selector(ProseView.selectAll(_:)))
    }

    func testMacHighlightPaletteResolvesAcrossAppearances() throws {
        let palette = try XCTUnwrap(HighlightColor.color(for: "#ffd54f"))
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertNotEqual(
            components(of: palette, under: light),
            components(of: palette, under: dark),
            "a shipped palette colour must map to a dark-mode variant on macOS"
        )
    }

    private func components(of color: NSColor, under appearance: NSAppearance) -> [CGFloat] {
        var resolved = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent]
    }
}

private final class TestPasteboard: ProseEditor.Pasteboard {
    var string: String?

    var hasStrings: Bool {
        string != nil
    }
}

private final class TestValidatedItem: NSObject, NSValidatedUserInterfaceItem {
    let action: Selector?
    let tag = 0

    init(action: Selector?) {
        self.action = action
    }
}

@MainActor
extension MacProseViewTests {
    // MARK: - Live block input rules (Phase 1)

    private func makeMacView(_ document: Document) -> ProseView {
        let view = ProseView(document: document)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testTypingHashSpaceConvertsToHeadingInMacView() {
        let view = makeMacView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: start, head: start))

        view.insertText("# ", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(view.document.root.content[0].type, "heading")
        XCTAssertEqual(view.document.root.content[0].attrs["level"], .int(1))
        XCTAssertEqual(view.document.root.content[0].plainText, "")
    }

    func testTypingGtSpaceWrapsInBlockquoteInMacView() {
        let view = makeMacView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: start, head: start))

        view.insertText("> ", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(view.document.root.content[0].type, "blockquote")
    }

    // MARK: - Live inline mark rules (Phase 3)

    private func emptyParaMacView() -> ProseView {
        let view = makeMacView(Document(.doc([.paragraph([])])))
        let start = view.core.document.endTextPosition
        view.core.setSelection(TextSelection(anchor: start, head: start))
        return view
    }

    private func type(_ text: String, into view: ProseView) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func typeLive(_ text: String, into view: ProseView) {
        for character in text { type(String(character), into: view) }
    }

    func testTypingStarItalicLeavesTrailingSpacePlainInMacView() {
        let view = emptyParaMacView()

        typeLive("*Italic* ", into: view)

        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["Italic", " "])
        XCTAssertEqual(runs.map(\.marks), [[.italic], []])
    }

    func testTypingBoldInMacView() {
        let view = emptyParaMacView()
        typeLive("**Bold**", into: view)
        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["Bold"])
        XCTAssertEqual(runs.map(\.marks), [[.bold]])
    }

    func testTypingCodePreservesPrecedingCharInMacView() {
        let view = emptyParaMacView()
        typeLive("a`Code`", into: view)
        let runs = view.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["a", "Code"])
        XCTAssertEqual(runs.map(\.marks), [[], [.code]])
    }

    // MARK: - Immediate Backspace revert (Phase 4)

    func testBackspaceAfterBlockShortcutRestoresLiteralInMacView() {
        let view = emptyParaMacView()
        type("# ", into: view)
        XCTAssertEqual(view.document.root.content[0].type, "heading")

        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.root.content[0].type, "paragraph")
        XCTAssertEqual(view.document.root.content[0].plainText, "# ")
    }

    func testBackspaceAfterInlineShortcutRestoresLiteralInMacView() {
        let view = emptyParaMacView()
        typeLive("*Italic*", into: view)
        XCTAssertEqual(view.document.root.content[0].content.first?.marks, [.italic])

        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.root.content[0].plainText, "*Italic*")
        XCTAssertEqual(view.document.root.content[0].content.map(\.marks), [[]])
    }
}
#endif
