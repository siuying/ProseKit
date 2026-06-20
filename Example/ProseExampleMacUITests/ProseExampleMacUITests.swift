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

    @MainActor
    func testMacEditorTypesAndDeletesText() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.textViews["Prose editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("z")
        var value = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(value.contains("z"))

        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        value = try XCTUnwrap(editor.value as? String)
        XCTAssertFalse(value.hasSuffix("z"))
    }
}
