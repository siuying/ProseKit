import XCTest
@testable import ProseModel

/// Every edit derives the new Document's block index from the old one
/// instead of re-walking the tree (issue 07). Document equality includes the
/// index, so comparing an edited document against a from-scratch rebuild of
/// the same root pins the derivation: any drift in starts, counts, or end
/// positions fails the assertion.
final class DerivedIndexTests: XCTestCase {
    private let document = Document(.doc([
        .heading(level: 1, [.text("Hello")]),
        .paragraph([.text("middle block")]),
        .paragraph([]),
        .paragraph([.text("end")]),
    ]))

    private func assertIndexMatchesRebuild(
        _ edited: Document, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(edited, Document(edited.root), label, file: file, line: line)
    }

    func testReplacingTextDerivesIndex() throws {
        let textStart = document.position(ofTextInBlockAt: 1)!
        let inserted = try document.replacingText(from: textStart + 6, to: textStart + 6, with: "of the ")
        assertIndexMatchesRebuild(inserted, "insertion")

        let deleted = try document.replacingText(from: textStart, to: textStart + 7, with: "")
        assertIndexMatchesRebuild(deleted, "deletion")

        let lastTextStart = document.position(ofTextInBlockAt: 3)!
        let atEnd = try document.replacingText(from: lastTextStart + 3, to: lastTextStart + 3, with: "!")
        assertIndexMatchesRebuild(atEnd, "insertion in last block")
    }

    func testMarkedInsertionDerivesIndex() throws {
        let textStart = document.position(ofTextInBlockAt: 1)!
        let marked = try document.replacingText(
            from: textStart + 6, to: textStart + 6, with: "bold", marks: [Mark(type: "bold")]
        )
        assertIndexMatchesRebuild(marked, "marked insertion")
    }

    func testSplitBlockDerivesIndex() throws {
        for blockIndex in [0, 1, 3] {
            let position = document.position(ofTextInBlockAt: blockIndex)! + 2
            let (split, _, _) = try document.splitBlock(at: position)
            assertIndexMatchesRebuild(split, "split block \(blockIndex)")
        }
    }

    func testJoinBackwardDerivesIndex() throws {
        let mergeAt = document.position(ofTextInBlockAt: 1)!
        let (merged, _, _) = try XCTUnwrap(document.joinBackward(at: mergeAt))
        assertIndexMatchesRebuild(merged, "merging join")

        let emptyAt = document.position(ofTextInBlockAt: 2)!
        let (removed, _, _) = try XCTUnwrap(document.joinBackward(at: emptyAt))
        assertIndexMatchesRebuild(removed, "empty-block join")
    }

    func testTogglingHeadingDerivesIndex() throws {
        let position = document.position(ofTextInBlockAt: 1)!
        let (toggled, _, _) = try document.togglingHeading(at: position, level: 2)
        assertIndexMatchesRebuild(toggled, "paragraph to heading")

        let (untoggled, _, _) = try document.togglingHeading(at: document.position(ofTextInBlockAt: 0)!, level: 1)
        assertIndexMatchesRebuild(untoggled, "heading to paragraph")
    }

    func testSettingMarksDerivesIndex() throws {
        let textStart = document.position(ofTextInBlockAt: 1)!
        let added = try document.addingMark(from: textStart, to: textStart + 6, mark: Mark(type: "bold"))
        assertIndexMatchesRebuild(added, "adding mark")

        let removed = try added.removingMark(from: textStart, to: textStart + 6, mark: Mark(type: "bold"))
        assertIndexMatchesRebuild(removed, "removing mark")
    }

    func testEditingDownToAnEmptyDocumentDerivesIndex() throws {
        let single = Document(.doc([.paragraph([]), .paragraph([])]))
        let (joined, _, _) = try XCTUnwrap(single.joinBackward(at: single.position(ofTextInBlockAt: 1)!))
        assertIndexMatchesRebuild(joined, "join down to one block")
    }
}
