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
        XCTAssertEqual(view.selectionLayer.selectionRects, view.core.selectionRects(for: view.core.selection))
        XCTAssertTrue(view.selectionLayer.drawsSelectionHighlight)
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
        let layer = MacSelectionLayerView()
        layer.selectionRects = [CGRect(x: 1, y: 2, width: 3, height: 4)]

        layer.setWindowIsKey(true)
        let active = layer.selectionHighlightColor
        layer.setWindowIsKey(false)

        XCTAssertTrue(layer.drawsSelectionHighlight)
        XCTAssertNotEqual(active, layer.selectionHighlightColor)
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
#endif
