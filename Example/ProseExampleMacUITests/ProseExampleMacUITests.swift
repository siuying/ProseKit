import XCTest

final class ProseExampleMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMacEditorRendersAndScrolls() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.textViews["Prose editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let value = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(value.contains("ProseExample macOS"))
        editor.swipeUp()
    }
}
