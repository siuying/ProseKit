import XCTest
@testable import ProseModel

final class PositionTests: XCTestCase {
    func testPositionsCountNodeBoundaryTokens() throws {
        let document = Fixtures.headingAndParagraph

        XCTAssertEqual(document.root.nodeSize, 16)
        XCTAssertEqual(document.position(ofBlockAt: 0), 1)
        XCTAssertEqual(document.position(ofTextInBlockAt: 0), 2)
        XCTAssertEqual(document.position(ofBlockAt: 1), 8)
        XCTAssertEqual(document.position(ofTextInBlockAt: 1), 9)
        XCTAssertEqual(document.endPosition, 15)
        XCTAssertEqual(document.endTextPosition, 14)
    }

    func testEndTextPositionUsesTheLastCaretablePositionInAnEmptyBlock() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
            .paragraph([]),
        ]))

        XCTAssertEqual(document.endTextPosition, 9)
    }
}

private enum Fixtures {
    static let headingAndParagraph = Document(.doc([
        .heading(level: 1, [.text("Hello")]),
        .paragraph([.text("world")]),
    ]))
}
