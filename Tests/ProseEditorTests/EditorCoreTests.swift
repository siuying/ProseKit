import XCTest
@testable import ProseEditor
@testable import ProseModel

@MainActor
final class EditorCoreTests: XCTestCase {
    func testCoreRelayoutsAfterDispatchingACommandAndAnswersGeometry() throws {
        let document = Document(.doc([
            .paragraph([.text("hello world")]),
        ]))
        let core = EditorCore(document: document, schema: .slice1)

        core.relayout(width: 320)
        let before = try XCTUnwrap(core.layoutBox)
        XCTAssertGreaterThan(before.frame.height, 0)

        core.setSelection(TextSelection(anchor: 2, head: 7))
        XCTAssertTrue(core.run(Commands.toggleMark(.bold)))

        XCTAssertEqual(core.document.root.content[0].content[0].marks, [.bold])
        XCTAssertEqual(core.selection, TextSelection(anchor: 2, head: 7))
        XCTAssertNotNil(core.lastTransaction?.changedRange)
        let after = try XCTUnwrap(core.layoutBox)
        XCTAssertEqual(after.frame.width, 320)
        XCTAssertGreaterThan(core.caretRect(for: core.selection.head).height, 0)
    }
}
