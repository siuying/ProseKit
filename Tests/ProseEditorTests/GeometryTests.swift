import XCTest
@testable import ProseEditor
@testable import ProseModel

final class GeometryTests: XCTestCase {
    func testCaretOffsetsReflectRealGlyphWidths() throws {
        let wide = Document(.doc([.paragraph([.text("WWWWW")])]))
        let narrow = Document(.doc([.paragraph([.text("lllll")])]))
        let engine = LayoutEngine(schema: .slice1)
        let mapper = GeometryMapper()

        // Caret after the five glyphs (text starts at position 2).
        let wideX = try mapper.caretRect(for: 7, in: engine.layout(wide, width: 320)).minX
        let narrowX = try mapper.caretRect(for: 7, in: engine.layout(narrow, width: 320)).minX

        XCTAssertGreaterThan(wideX, narrowX * 1.5)
    }

    func testClosestPositionAndCaretRectAreConsistentAcrossWrappedLines() throws {
        let text = "the quick brown fox jumps over the lazy dog"
        let document = Document(.doc([
            .paragraph([.text(text)]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 120)
        let mapper = GeometryMapper()
        XCTAssertGreaterThan(layout.children[0].lineFragments.count, 1, "expected the paragraph to wrap")

        for position in 2...(2 + text.count) {
            let rect = mapper.caretRect(for: position, in: layout)
            let roundTripped = mapper.closestPosition(to: CGPoint(x: rect.midX, y: rect.midY), in: layout)
            XCTAssertEqual(roundTripped, position, "round trip failed at position \(position)")
        }
    }

    func testSelectionRectsAlignWithCaretRectsAcrossLineFragments() throws {
        let document = Document(.doc([
            .paragraph([.text("the quick brown fox jumps over the lazy dog")]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 120)
        let mapper = GeometryMapper()
        let fragments = layout.children[0].lineFragments
        XCTAssertGreaterThan(fragments.count, 1, "expected the paragraph to wrap")

        // Select from mid-first-line to mid-second-line.
        let anchor = fragments[0].positionRange.lowerBound + 2
        let head = fragments[1].positionRange.lowerBound + 3
        let rects = mapper.selectionRects(for: TextSelection(anchor: anchor, head: head), in: layout)

        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, mapper.caretRect(for: anchor, in: layout).minX, accuracy: 0.5)
        XCTAssertEqual(rects[0].minY, fragments[0].frame.minY, accuracy: 0.5)
        XCTAssertEqual(rects[1].minX, fragments[1].frame.minX, accuracy: 0.5)
        XCTAssertEqual(rects[1].maxX, mapper.caretRect(for: head, in: layout).minX, accuracy: 0.5)
        XCTAssertGreaterThan(rects[0].width, 0)
        XCTAssertGreaterThan(rects[1].width, 0)
    }

    func testMarksAffectMeasuredGlyphWidths() throws {
        let regular = Document(.doc([.paragraph([.text("emphasis")])]))
        let bold = Document(.doc([.paragraph([.text("emphasis", marks: [.bold])])]))
        let engine = LayoutEngine(schema: .slice1)
        let mapper = GeometryMapper()

        let regularX = try mapper.caretRect(for: 10, in: engine.layout(regular, width: 320)).minX
        let boldX = try mapper.caretRect(for: 10, in: engine.layout(bold, width: 320)).minX

        XCTAssertGreaterThan(boldX, regularX)
    }

    func testEmptyParagraphHasACaretableLineFragment() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 320)
        let mapper = GeometryMapper()

        let fragment = layout.children[1].lineFragments[0]
        XCTAssertGreaterThan(fragment.typographicHeight, 0)

        let position = layout.children[1].positionRange.lowerBound + 1
        let rect = mapper.caretRect(for: position, in: layout)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.5)
        XCTAssertEqual(mapper.closestPosition(to: CGPoint(x: rect.midX, y: rect.midY), in: layout), position)
    }
}
