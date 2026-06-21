import XCTest
import ProseModel
@testable import ProseKitYjs

final class MarkAttributesTests: XCTestCase {
    func testEncodesMarksAsKeyedAttributes() {
        let attributes = MarkAttributes.attributes(for: [.bold, .link(href: "https://example.com")])
        XCTAssertEqual(attributes["bold"], [:])
        XCTAssertEqual(attributes["link"], ["href": .string("https://example.com")])
    }

    func testPlainMarksRoundTrip() {
        let original = [Mark.bold, Mark.link(href: "https://example.com")]
        let restored = MarkAttributes.marks(from: MarkAttributes.attributes(for: original))
        XCTAssertEqual(Set(restored), Set(original))
    }

    // MARK: - Opaque preservation (#70)

    func testPreservesHashedKeyVerbatim() {
        // An overlapping-mark key (name--XXXXXXXX) ProseKit does not produce is
        // carried opaquely as the mark type and re-emitted byte-for-byte.
        let marks = MarkAttributes.marks(from: ["comment--AbCd1234": ["id": .int(7)]])
        XCTAssertEqual(marks, [Mark(type: "comment--AbCd1234", attrs: ["id": .int(7)])])
        XCTAssertEqual(
            MarkAttributes.attributes(for: marks),
            ["comment--AbCd1234": ["id": .int(7)]]
        )
    }

    func testPreservesYchangeKey() {
        // ychange is reserved by y-prosemirror; ProseKit never authors it, but a
        // received ychange key is preserved rather than dropped.
        let marks = MarkAttributes.marks(from: ["ychange": ["user": .string("a")]])
        XCTAssertEqual(marks, [Mark(type: "ychange", attrs: ["user": .string("a")])])
        XCTAssertEqual(MarkAttributes.attributes(for: marks)["ychange"], ["user": .string("a")])
    }

    func testPreservesUnknownMarkName() {
        let marks = MarkAttributes.marks(from: ["spoiler": [:]])
        XCTAssertEqual(marks, [Mark(type: "spoiler", attrs: [:])])
        XCTAssertEqual(MarkAttributes.attributes(for: marks)["spoiler"], [:])
    }
}
