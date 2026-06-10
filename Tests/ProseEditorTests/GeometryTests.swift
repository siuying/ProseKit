import XCTest
@testable import ProseEditor
@testable import ProseModel

final class GeometryTests: XCTestCase {
    func testClosestPositionAndCaretRectAreConsistentAcrossWrappedLines() throws {
        let document = Document(.doc([
            .paragraph([.text("abcdefghij")]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 54)
        let mapper = GeometryMapper(characterWidth: 10)

        let position = mapper.closestPosition(to: CGPoint(x: 20, y: 25), in: layout)
        let rect = mapper.caretRect(for: position, in: layout)

        XCTAssertEqual(position, 9)
        XCTAssertEqual(mapper.closestPosition(to: CGPoint(x: rect.midX, y: rect.midY), in: layout), position)
    }

    func testSelectionRectsCoverTheSelectedGlyphsAcrossLineFragments() throws {
        let document = Document(.doc([
            .paragraph([.text("abcdefghij")]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 54)
        let mapper = GeometryMapper(characterWidth: 10)

        let rects = mapper.selectionRects(for: TextSelection(anchor: 4, head: 10), in: layout)

        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, 20)
        XCTAssertEqual(rects[1].minX, 0)
    }
}
