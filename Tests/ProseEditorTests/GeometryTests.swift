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
        let blockStart = layout.children[0].positionRange.lowerBound
        let anchor = blockStart + fragments[0].positionRange.lowerBound + 2
        let head = blockStart + fragments[1].positionRange.lowerBound + 3
        let rects = mapper.selectionRects(for: TextSelection(anchor: anchor, head: head), in: layout)

        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, mapper.caretRect(for: anchor, in: layout).minX, accuracy: 0.5)
        XCTAssertEqual(rects[0].minY, layout.children[0].frame.minY + fragments[0].frame.minY, accuracy: 0.5)
        XCTAssertEqual(rects[1].minX, layout.children[0].frame.minX + fragments[1].frame.minX, accuracy: 0.5)
        XCTAssertEqual(rects[1].maxX, mapper.caretRect(for: head, in: layout).minX, accuracy: 0.5)
        XCTAssertGreaterThan(rects[0].width, 0)
        XCTAssertGreaterThan(rects[1].width, 0)
    }

    func testPositionBeforeAndAfterStepThroughTextAndAcrossBlocks() throws {
        // paragraph "ab" occupies 1..<5 (text 2...4), paragraph "cd" 5..<9 (text 6...8).
        let document = Document(.doc([
            .paragraph([.text("ab")]),
            .paragraph([.text("cd")]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 320)
        let mapper = GeometryMapper()

        XCTAssertEqual(mapper.position(after: 2, in: layout), 3)
        XCTAssertEqual(mapper.position(after: 4, in: layout), 6, "right at block end jumps to next block's text start")
        XCTAssertEqual(mapper.position(after: 8, in: layout), 8, "clamped at document text end")
        XCTAssertEqual(mapper.position(before: 3, in: layout), 2)
        XCTAssertEqual(mapper.position(before: 6, in: layout), 4, "left at block start jumps to previous block's text end")
        XCTAssertEqual(mapper.position(before: 2, in: layout), 2, "clamped at document text start")
    }

    func testPositionAboveAndBelowMoveBetweenLinesPreservingX() throws {
        let document = Document(.doc([
            .paragraph([.text("the quick brown fox jumps over the lazy dog")]),
            .paragraph([.text("tail")]),
        ]))
        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 120)
        let mapper = GeometryMapper()
        let fragments = layout.children[0].lineFragments
        XCTAssertGreaterThan(fragments.count, 1, "expected the paragraph to wrap")

        func owningFragment(of position: Position) -> LineFragment? {
            for block in layout.children {
                let local = position - block.positionRange.lowerBound
                if let fragment = block.lineFragments.first(where: {
                    $0.positionRange.contains(local) || $0.positionRange.upperBound == local
                }) {
                    return fragment
                }
            }
            return nil
        }

        // Down from mid-first-line lands on the second line near the same x.
        let blockStart = layout.children[0].positionRange.lowerBound
        let start = blockStart + fragments[0].positionRange.lowerBound + 3
        let below = mapper.position(below: start, in: layout)
        XCTAssertEqual(owningFragment(of: below)?.positionRange, fragments[1].positionRange)
        let startX = mapper.caretRect(for: start, in: layout).minX
        XCTAssertEqual(mapper.caretRect(for: below, in: layout).minX, startX, accuracy: 12)

        // And back up to the first line, near the same x.
        let above = mapper.position(above: below, in: layout)
        XCTAssertEqual(owningFragment(of: above)?.positionRange, fragments[0].positionRange)
        XCTAssertEqual(mapper.caretRect(for: above, in: layout).minX, startX, accuracy: 12)

        // Down from the paragraph's last line crosses into the next block.
        let crossed = mapper.position(below: blockStart + fragments.last!.positionRange.lowerBound + 1, in: layout)
        XCTAssertEqual(owningFragment(of: crossed)?.positionRange, layout.children[1].lineFragments[0].positionRange)

        // Clamps: up from the first line and down from the last line hit the text edges.
        XCTAssertEqual(mapper.position(above: start, in: layout), 2)
        let lastTextPosition = layout.children[1].positionRange.lowerBound + layout.children[1].lineFragments[0].positionRange.upperBound
        XCTAssertEqual(mapper.position(below: crossed, in: layout), lastTextPosition)
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
