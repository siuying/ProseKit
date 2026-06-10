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
