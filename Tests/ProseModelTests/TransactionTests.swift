import XCTest
@testable import ProseModel

final class TransactionTests: XCTestCase {
    func testTransactionCarriesOriginAndResultingSelection() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let transaction = Transaction(
            steps: [ReplaceStep(from: 7, to: 7, insertText: "!")],
            selection: TextSelection(anchor: 8, head: 8),
            origin: .local
        )

        let applied = try transaction.apply(to: document)

        XCTAssertEqual(applied.document.plainText, "hello!")
        XCTAssertEqual(applied.selection, TextSelection(anchor: 8, head: 8))
        XCTAssertEqual(applied.origin, .local)
        XCTAssertEqual(applied.changedRange, 7..<8)
    }

    func testTransactionMapsEarlierChangedRangeThroughLaterSteps() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let transaction = Transaction(
            steps: [
                ReplaceStep(from: 3, to: 3, insertText: "X"),
                ReplaceStep(from: 8, to: 8, insertText: "!"),
            ],
            selection: TextSelection(anchor: 9, head: 9),
            origin: .local
        )

        let applied = try transaction.apply(to: document)

        XCTAssertEqual(applied.document.plainText, "hXello!")
        XCTAssertEqual(applied.changedRange, 3..<9)
    }

    func testSelectionMapsAcrossReplacement() {
        let selection = TextSelection(anchor: 4, head: 7)
        let mapping = Mapping([ReplaceStep(from: 3, to: 3, insertText: "XX")])

        XCTAssertEqual(selection.mapped(through: mapping), TextSelection(anchor: 6, head: 9))
    }
}
