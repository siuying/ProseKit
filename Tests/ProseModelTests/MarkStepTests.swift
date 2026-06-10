import XCTest
@testable import ProseModel

final class MarkStepTests: XCTestCase {
    func testAddMarkStepAppliesAndInverts() throws {
        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let step = AddMarkStep(from: 2, to: 7, mark: .bold)

        let applied = try step.apply(to: document).document
        XCTAssertEqual(applied.root.content[0].content[0].marks, [.bold])

        let restored = try step.inverted(in: document).apply(to: applied).document
        XCTAssertEqual(restored, document)
    }

    func testRemoveMarkStepAppliesAndInverts() throws {
        let document = Document(.doc([
            .paragraph([.text("hello", marks: [.bold])]),
        ]))
        let step = RemoveMarkStep(from: 2, to: 7, mark: .bold)

        let applied = try step.apply(to: document).document
        XCTAssertEqual(applied.root.content[0].content[0].marks, [])

        let restored = try step.inverted(in: document).apply(to: applied).document
        XCTAssertEqual(restored, document)
    }
}
