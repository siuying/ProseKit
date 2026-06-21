import XCTest
import ProseModel
@testable import ProseKitYjs

final class MarkAttributesTests: XCTestCase {
    // MARK: - markName (yattr2markname)

    func testPlainMarkNameIsUnchanged() {
        XCTAssertEqual(MarkAttributes.markName(forKey: "bold"), "bold")
        XCTAssertEqual(MarkAttributes.markName(forKey: "link"), "link")
    }

    func testStripsOverlappingMarkHashSuffix() {
        // y-prosemirror keys an overlapping mark as `name--XXXXXXXX` (8 base64 chars).
        XCTAssertEqual(MarkAttributes.markName(forKey: "comment--AbCd1234"), "comment")
        XCTAssertEqual(MarkAttributes.markName(forKey: "highlight--aB3/xY9+"), "highlight")
    }

    func testDoesNotStripNonHashDoubleDash() {
        // A `--` not followed by exactly 8 base64 chars is part of the name.
        XCTAssertEqual(MarkAttributes.markName(forKey: "foo--bar"), "foo--bar")
        XCTAssertEqual(MarkAttributes.markName(forKey: "foo--toolongtobeahash"), "foo--toolongtobeahash")
    }

    // MARK: - attributes / marks

    func testEncodesMarksAsNameKeyedAttributes() {
        let attributes = MarkAttributes.attributes(for: [.bold, .link(href: "https://example.com")])
        XCTAssertEqual(attributes["bold"], [:])
        XCTAssertEqual(attributes["link"], ["href": .string("https://example.com")])
    }

    func testSkipsYchangeOnEncodeAndDecode() {
        XCTAssertNil(MarkAttributes.attributes(for: [Mark(type: "ychange")])["ychange"])
        XCTAssertTrue(MarkAttributes.marks(from: ["ychange": ["user": .string("a")]]).isEmpty)
    }

    func testDecodeStripsHashAndRebuildsMark() {
        let marks = MarkAttributes.marks(from: ["comment--AbCd1234": ["id": .int(7)]])
        XCTAssertEqual(marks, [Mark(type: "comment", attrs: ["id": .int(7)])])
    }

    func testMarksRoundTripThroughAttributes() {
        let original = [Mark.bold, Mark.link(href: "https://example.com")]
        let restored = MarkAttributes.marks(from: MarkAttributes.attributes(for: original))
        XCTAssertEqual(Set(restored), Set(original))
    }
}
