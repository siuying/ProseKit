import XCTest
import CoreGraphics
@testable import ProseEditor
@testable import ProseModel

final class LayoutTests: XCTestCase {
    func testLayoutCreatesOneLeafBoxPerLeafBlockAndStacksThemVertically() throws {
        let document = Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([.text("world")]),
        ]))

        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 320)

        XCTAssertEqual(layout.children.count, 2)
        XCTAssertEqual(layout.children.map(\.kind), [.leafBlock, .leafBlock])
        XCTAssertEqual(layout.children.map(\.node.type), ["heading", "paragraph"])
        XCTAssertGreaterThan(layout.children[1].frame.minY, layout.children[0].frame.minY)
        XCTAssertGreaterThan(layout.children[0].lineFragments[0].typographicHeight, layout.children[1].lineFragments[0].typographicHeight)
    }

    func testLineFragmentsBreakAtWordBoundariesAndCoverAllText() throws {
        let text = "the quick brown fox jumps over the lazy dog"
        let document = Document(.doc([.paragraph([.text(text)])]))

        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 120)

        let fragments = layout.children[0].lineFragments
        XCTAssertGreaterThan(fragments.count, 1, "expected the paragraph to wrap")
        XCTAssertEqual(fragments.map(\.text).joined(), text)
        for fragment in fragments.dropLast() {
            XCTAssertTrue(fragment.text.hasSuffix(" "), "wrapped line should break at a word boundary: '\(fragment.text)'")
        }
    }

    func testLeafLineFragmentsUseBoxRelativeGeometryAndPositions() throws {
        let document = Document(.doc([
            .paragraph([.text("alpha")]),
            .paragraph([.text("beta")]),
        ]))

        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 320)

        let second = layout.children[1]
        XCTAssertGreaterThan(second.frame.minY, 0)
        XCTAssertEqual(second.lineFragments[0].frame.minY, 0)
        XCTAssertEqual(second.lineFragments[0].positionRange, 1..<5)

        let mapper = GeometryMapper()
        let absoluteTextStart = second.positionRange.lowerBound + second.lineFragments[0].positionRange.lowerBound
        XCTAssertEqual(
            mapper.caretRect(for: absoluteTextStart, in: layout).minY,
            second.frame.minY,
            accuracy: 0.5
        )
    }
}
