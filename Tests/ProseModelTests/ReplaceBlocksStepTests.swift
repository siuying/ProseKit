import XCTest
@testable import ProseModel

final class ReplaceBlocksStepTests: XCTestCase {
    private func doc() -> Document {
        Document(.doc([
            .paragraph([.text("one")]),
            .paragraph([.text("two")]),
            .paragraph([.text("three")]),
        ]))
    }

    func testReplacesABlockInPlaceChangingTypeAndAttrs() throws {
        let document = doc()
        // Replace block 1 ("two") with a heading carrying the same text.
        let from = try XCTUnwrap(document.position(ofBlockAt: 1))
        let removed = document.root.content[1].nodeSize
        let step = ReplaceBlocksStep(
            blockRange: 1..<2,
            blocks: [.heading(level: 2, [.text("two")])],
            from: from,
            removedSize: removed
        )

        let applied = try step.apply(to: document)
        XCTAssertEqual(applied.document.root.content.map(\.type), ["paragraph", "heading", "paragraph"])
        XCTAssertEqual(applied.document.root.content[1].attrs["level"], .int(2))
        XCTAssertEqual(applied.document.plainText, "onetwothree")
    }

    func testMapShiftsPositionsAfterASizeChange() throws {
        let document = doc()
        let from = try XCTUnwrap(document.position(ofBlockAt: 1))
        let removed = document.root.content[1].nodeSize // "two" -> 2 + 3 = 5
        // Replace "two" (size 5) with "twoXX" (size 7): +2 after the block.
        let step = ReplaceBlocksStep(
            blockRange: 1..<2,
            blocks: [.paragraph([.text("twoXX")])],
            from: from,
            removedSize: removed
        )

        XCTAssertEqual(step.map(from - 1), from - 1)       // before: unchanged
        XCTAssertEqual(step.map(from + removed + 3), from + removed + 3 + 2) // after: shifted by +2
    }

    func testInvertRestoresOriginalBlocks() throws {
        let document = doc()
        let from = try XCTUnwrap(document.position(ofBlockAt: 0))
        let removed = document.root.content[0].nodeSize + document.root.content[1].nodeSize
        let step = ReplaceBlocksStep(
            blockRange: 0..<2,
            blocks: [.heading(level: 1, [.text("merged")])],
            from: from,
            removedSize: removed
        )

        let applied = try step.apply(to: document)
        XCTAssertEqual(applied.document.root.content.map(\.type), ["heading", "paragraph"])

        let inverse = try step.inverted(in: document)
        let restored = try inverse.apply(to: applied.document).document
        XCTAssertEqual(restored, document)
    }
}
