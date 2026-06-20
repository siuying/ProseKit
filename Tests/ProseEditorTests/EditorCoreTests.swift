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

    func testCoreExposesSharedEditorKeyBindings() throws {
        let bindings = EditorCore.sharedKeyBindings

        XCTAssertEqual(bindings.map(\.key), [.character("b"), .character("i"), .tab, .tab])
        XCTAssertEqual(bindings.map(\.modifiers), [.command, .command, [], .shift])
        XCTAssertEqual(bindings.map(\.action), [.toggleBold, .toggleItalic, .sinkListItem, .liftListItem])

        let document = Document(.doc([
            .paragraph([.text("hello")]),
        ]))
        let core = EditorCore(document: document)
        let start = try XCTUnwrap(core.document.position(ofTextInBlockAt: 0))
        core.setSelection(TextSelection(anchor: start, head: start + 5))

        XCTAssertTrue(core.runKeyBindingAction(.toggleBold))
        XCTAssertEqual(core.document.root.content[0].content[0].marks, [.bold])
    }
}
