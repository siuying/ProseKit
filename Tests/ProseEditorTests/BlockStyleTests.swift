#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

/// BlockStyle resolves Marks to CoreText attributes. An unknown Mark must
/// contribute nothing — the run renders exactly as plain text (ADR 0006).
final class BlockStyleTests: XCTestCase {
    func testUnknownMarkRendersAsPlainText() {
        let plain = Node.paragraph([.text("Hello")])
        let marked = Node.paragraph([.text("Hello", marks: [Mark(type: "xyzzy")])])

        XCTAssertEqual(
            BlockStyle.attributedString(for: marked),
            BlockStyle.attributedString(for: plain),
            "an unsupported mark must not change any CoreText styling"
        )
    }

    func testKnownMarkStillChangesStyling() {
        let plain = Node.paragraph([.text("Hello")])
        let bold = Node.paragraph([.text("Hello", marks: [.bold])])

        XCTAssertNotEqual(
            BlockStyle.attributedString(for: bold),
            BlockStyle.attributedString(for: plain),
            "bold must still render differently from plain text"
        )
    }

    func testUnderlineMarkSetsCoreTextUnderlineAttribute() {
        let node = Node.paragraph([.text("Hello", marks: [Mark(type: "underline")])])
        let attributed = BlockStyle.attributedString(for: node)

        let underline = attributed.attribute(
            NSAttributedString.Key(kCTUnderlineStyleAttributeName as String),
            at: 0,
            effectiveRange: nil
        )
        XCTAssertNotNil(underline, "underline mark must set the CoreText underline attribute (CTLine draws it)")
    }

    func testStrikeMarkFlagsRunForManualDrawing() {
        let node = Node.paragraph([.text("Hello", marks: [Mark(type: "strike")])])
        let attributed = BlockStyle.attributedString(for: node)

        let flagged = attributed.attribute(BlockStyle.strikethroughAttributeName, at: 0, effectiveRange: nil)
        XCTAssertNotNil(flagged, "strike has no CoreText attribute; the run must be flagged for manual drawing")
    }
}
#endif
