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
    }
}
