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
