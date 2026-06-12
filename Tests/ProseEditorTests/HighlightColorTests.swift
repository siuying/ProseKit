#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

final class HighlightColorTests: XCTestCase {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    func testParsesHexColors() {
        XCTAssertNotNil(HighlightColor.color(for: "#ffd54f"))
        XCTAssertNotNil(HighlightColor.color(for: "#abc"))
    }

    func testUnparseableColorReturnsNil() {
        // A CSS variable or named colour we don't understand: preserved in the
        // model, but no background is drawn (ADR 0005).
        XCTAssertNil(HighlightColor.color(for: "var(--my-color)"))
        XCTAssertNil(HighlightColor.color(for: "rebeccapurple"))
        XCTAssertNil(HighlightColor.color(for: ""))
    }

    func testKnownPaletteColorIsDynamicAcrossModes() {
        let palette = HighlightColor.color(for: "#ffd54f")!
        XCTAssertNotEqual(
            palette.resolvedColor(with: light),
            palette.resolvedColor(with: dark),
            "a shipped palette colour must map to a dark-mode variant"
        )
    }

    func testArbitraryColorIsStableAcrossModes() {
        let arbitrary = HighlightColor.color(for: "#123456")!
        XCTAssertEqual(
            arbitrary.resolvedColor(with: light),
            arbitrary.resolvedColor(with: dark),
            "a colour outside the palette renders literally in both modes"
        )
    }

    func testHighlightMarkAttachesRawValue() {
        let node = Node.paragraph([.text("hi", marks: [Mark(type: "highlight", attrs: ["color": .string("#ffd54f")])])])
        let attributed = BlockStyle.attributedString(for: node)
        let value = attributed.attribute(BlockStyle.highlightAttributeName, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(value, "#ffd54f", "the raw colour value is carried verbatim to the draw path")
    }
}
#endif
