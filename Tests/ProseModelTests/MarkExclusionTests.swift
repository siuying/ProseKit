import XCTest
@testable import ProseModel

final class MarkExclusionTests: XCTestCase {
    func testCodeExcludesOtherMarksWhenAdded() {
        let result = MarkRules.adding(.code, to: [.bold, .italic])
        XCTAssertEqual(result, [.code], "adding code drops every other mark")
    }

    func testMarkExcludedByCodeIsNotAdded() {
        let result = MarkRules.adding(.bold, to: [.code])
        XCTAssertEqual(result, [.code], "a code run rejects other marks")
    }

    func testSuperscriptAndSubscriptAreMutuallyExclusive() {
        let sup = Mark(type: "superscript")
        let sub = Mark(type: "subscript")
        XCTAssertEqual(MarkRules.adding(sup, to: [sub]), [sup])
        XCTAssertEqual(MarkRules.adding(sub, to: [sup]), [sub])
    }

    func testUnrelatedMarksCoexist() {
        XCTAssertEqual(MarkRules.adding(.italic, to: [.bold]), [.bold, .italic])
    }

    func testAddingAPresentMarkIsIdempotent() {
        XCTAssertEqual(MarkRules.adding(.bold, to: [.bold]), [.bold])
    }

    func testDocumentAddingCodeOverBoldLeavesCodeOnly() throws {
        let document = Document(.doc([.paragraph([.text("hello", marks: [.bold])])]))
        let result = try AddMarkStep(from: 2, to: 7, mark: .code).apply(to: document).document
        XCTAssertEqual(result.root.content[0].content[0].marks, [.code])
    }
}
