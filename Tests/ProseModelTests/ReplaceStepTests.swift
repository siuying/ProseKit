import XCTest
@testable import ProseModel

final class ReplaceStepTests: XCTestCase {
    func testReplaceStepAppliesAndInvertsTextInsideParagraph() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let step = ReplaceStep(from: 3, to: 6, insertText: "y")

        let applied = try step.apply(to: document)
        XCTAssertEqual(applied.document.plainText, "hyo")

        let inverse = try step.inverted(in: document)
        let restored = try inverse.apply(to: applied.document).document
        XCTAssertEqual(restored, document)
    }

    func testReplaceStepAcrossBlocksMergesThemPreservingMarks() throws {
        let document = Document(.doc([
            .paragraph([.text("plain "), .text("bold", marks: [.bold])]),
            .paragraph([.text("ital", marks: [.italic]), .text(" tail")]),
        ]))

        // From inside the bold run to inside the italic run of the next block.
        let step = ReplaceStep(from: 10, to: 16, insertText: "")
        let applied = try step.apply(to: document)

        XCTAssertEqual(applied.document.root.content.count, 1)
        XCTAssertEqual(applied.document.plainText, "plain boal tail")
        let runs = applied.document.root.content[0].content
        XCTAssertEqual(runs.map(\.text), ["plain ", "bo", "al", " tail"])
        XCTAssertEqual(runs[1].marks, [.bold], "the cut bold run keeps its mark")
        XCTAssertEqual(runs[2].marks, [.italic], "the cut italic run keeps its mark")
    }

    func testMappingRemapsPositionsAroundReplaceStep() {
        let step = ReplaceStep(from: 3, to: 6, insertText: "y")
        let mapping = Mapping([step])

        XCTAssertEqual(mapping.map(2), 2)
        XCTAssertEqual(mapping.map(3), 3)
        XCTAssertEqual(mapping.map(4), 4)
        XCTAssertEqual(mapping.map(6), 4)
        XCTAssertEqual(mapping.map(7), 5)
    }
}
