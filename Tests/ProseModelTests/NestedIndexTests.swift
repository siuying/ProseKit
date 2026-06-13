import XCTest
@testable import ProseModel

/// The leaf-block tiling index (ADR 0007): a nested document is indexed by its
/// leaf blocks (textblocks) in document order, with absolute Positions and the
/// "\n"-joined character space treating each leaf boundary as one "\n".
final class NestedIndexTests: XCTestCase {
    // doc > [ blockquote > [ p("ab"), p("cd") ], p("ef") ]
    private let document = Document(.doc([
        .blockquote([.paragraph([.text("ab")]), .paragraph([.text("cd")])]),
        .paragraph([.text("ef")]),
    ]))

    func testEnumeratesLeafBlocksInDocumentOrder() {
        XCTAssertEqual(document.blockCount, 3)
        // Opening-token Positions of each leaf, accounting for container tokens.
        XCTAssertEqual(document.position(ofBlockAt: 0), 2)  // p("ab"), inside blockquote
        XCTAssertEqual(document.position(ofBlockAt: 1), 6)  // p("cd")
        XCTAssertEqual(document.position(ofBlockAt: 2), 11) // p("ef"), top level
        XCTAssertEqual(document.textCount(ofBlockAt: 0), 2)
        XCTAssertEqual(document.textCount(ofBlockAt: 1), 2)
        XCTAssertEqual(document.textCount(ofBlockAt: 2), 2)
    }

    func testBlockInfoReturnsTheLeafNode() {
        XCTAssertEqual(document.blockInfo(containing: 7)?.node.plainText, "cd")
        XCTAssertEqual(document.blockInfo(containing: 3)?.node.plainText, "ab")
        XCTAssertEqual(document.blockInfo(containing: 12)?.node.plainText, "ef")
    }

    func testCharacterSpaceJoinsLeavesWithNewlines() {
        XCTAssertEqual(
            document.plainText(from: document.startTextPosition, to: document.endTextPosition),
            "ab\ncd\nef"
        )
        let cPos = document.position(ofTextInBlockAt: 1)! // textStart of p("cd")
        XCTAssertEqual(document.characterOffset(of: cPos), 3) // 'c' in "ab\ncd\nef"
        XCTAssertEqual(document.position(atCharacterOffset: 3), cPos)
    }

    func testTotalTextCountExcludesSeparators() {
        XCTAssertEqual(document.totalTextCount, 6) // ab + cd + ef
    }

    func testIndexIsStableAcrossRebuild() {
        XCTAssertEqual(document, Document(document.root))
    }

    func testFlatDocumentStillIndexesByTopLevelBlocks() {
        let flat = Document(.doc([.paragraph([.text("ab")]), .paragraph([.text("cd")])]))
        XCTAssertEqual(flat.blockCount, 2)
        XCTAssertEqual(flat.position(ofBlockAt: 0), 1)
        XCTAssertEqual(flat.position(ofBlockAt: 1), 5)
    }
}
