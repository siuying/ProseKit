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
        XCTAssertTrue(view.hasVerticalScroller)
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
