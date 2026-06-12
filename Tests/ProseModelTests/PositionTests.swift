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

    /// blockInfo is a binary search over the precomputed block index; it must
    /// agree with the original linear scan at every position, including the
    /// block-boundary ties (end of block i == start of block i+1 belongs to
    /// block i) and out-of-range positions.
    func testBlockInfoMatchesLinearScanAtEveryPosition() throws {
        let documents = [
            Fixtures.headingAndParagraph,
            Document(.doc([
                .paragraph([.text("hello")]),
                .paragraph([]),
                .paragraph([.text("a")]),
                .heading(level: 2, [.text("worlds beyond")]),
            ])),
            Document(.doc([.paragraph([])])),
            Document(.doc([])),
        ]
        for document in documents {
            for position in -1...(document.endPosition + 2) {
                let expected = linearBlockInfo(in: document, containing: position)
                let actual = document.blockInfo(containing: position)
                XCTAssertEqual(actual?.index, expected?.index, "position \(position)")
                XCTAssertEqual(actual?.start, expected?.start, "position \(position)")
                XCTAssertEqual(actual?.node, expected?.node, "position \(position)")
            }
        }
    }

    private func linearBlockInfo(in document: Document, containing position: Position) -> BlockInfo? {
        var start = 1
        for (index, block) in document.root.content.enumerated() {
            let end = start + block.nodeSize
            if position >= start, position <= end {
                return BlockInfo(index: index, node: block, start: start)
            }
            start = end
        }
        return nil
    }

    func testBlockIndexAccessors() throws {
        let document = Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([]),
            .paragraph([.text("world")]),
        ]))

        XCTAssertEqual(document.blockCount, 3)
        XCTAssertEqual(document.textCount(ofBlockAt: 0), 5)
        XCTAssertEqual(document.textCount(ofBlockAt: 1), 0)
        XCTAssertEqual(document.textCount(ofBlockAt: 2), 5)
        XCTAssertNil(document.textCount(ofBlockAt: 3))
        XCTAssertEqual(document.textCharacters(beforeBlockAt: 0), 0)
        XCTAssertEqual(document.textCharacters(beforeBlockAt: 2), 5)
        XCTAssertEqual(document.totalTextCount, 10)
        XCTAssertEqual(Document(.doc([])).totalTextCount, 0)
    }
}

private enum Fixtures {
    static let headingAndParagraph = Document(.doc([
        .heading(level: 1, [.text("Hello")]),
        .paragraph([.text("world")]),
    ]))
}
