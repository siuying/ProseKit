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

    @MainActor
    func testMacEditorCopiesPastesAndCutsSelection() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.textViews["Prose editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeKey(.rightArrow, modifierFlags: [.command])
        editor.typeText("CLIP")

        editor.typeKey(.leftArrow, modifierFlags: [.shift])
        editor.typeKey("c", modifierFlags: [.command])
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeKey("v", modifierFlags: [.command])

        var value = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(value.contains("CLIPP"))

        editor.typeKey(.leftArrow, modifierFlags: [.shift])
        editor.typeKey("x", modifierFlags: [.command])

        value = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(value.contains("CLIP"))
        XCTAssertFalse(value.contains("CLIPP"))
    }
}
