import XCTest

/// Types through the real input stack — keyboard, autocorrect, tokenizer,
/// UITextInteraction — which the package benchmarks bypass by calling
/// insertText directly. Guards against the 2026-06-12 live-keyboard stall
/// (O(blocks²) document reads between keystrokes; see
/// .scratch/editing-performance/issues/04-live-keyboard-path-stall.md):
/// before the fix, focusing an 800-paragraph document stalled the main
/// thread for ~23 seconds and every keystroke cost ~180 ms.
final class ProseExampleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// ProseView is a UIScrollView hosting a UITextInteraction; depending on
    /// the OS it surfaces as a text view or a scroll view.
    @MainActor
    private func editorElement(in app: XCUIApplication) -> XCUIElement {
        let asTextView = app.textViews.firstMatch
        if asTextView.waitForExistence(timeout: 5) { return asTextView }
        return app.scrollViews.firstMatch
    }

    /// Without -paragraphs the app boots into the demo list; tapping a row
    /// must push a working full-screen editor.
    @MainActor
    func testDemoListPushesAFullScreenEditor() throws {
        let app = XCUIApplication()
        app.launch()

        let row = app.staticTexts["Rich Text Basics"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let editor = editorElement(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        sleep(2)
        app.typeText("a")
    }

    @MainActor
    func testLiveTypingAroundAParagraphBreakStaysResponsive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paragraphs", "800"]
        app.launch()

        // Tap the editor so the XCUI event synthesizer sees keyboard focus
        // (programmatic becomeFirstResponder is not enough for it).
        let editor = editorElement(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        sleep(2)

        func timedType(_ text: String, label: String) -> TimeInterval {
            let start = Date()
            app.typeText(text)
            let elapsed = Date().timeIntervalSince(start)
            print("[live-typing] \(label): \(String(format: "%.3f", elapsed))s")
            return elapsed
        }

        // XCUITest event synthesis has its own per-keystroke overhead of
        // roughly a second, so the bound is deliberately loose; the bug this
        // guards against blew past it by an order of magnitude.
        let budget: TimeInterval = 5
        XCTAssertLessThan(timedType("a", label: "first char after focusing"), budget)
        XCTAssertLessThan(timedType("\n", label: "Return (new line)"), budget)
        XCTAssertLessThan(timedType("b", label: "first char after Return"), budget)
        XCTAssertLessThan(timedType("c", label: "second char after Return"), budget)
    }

    /// Pins the cost ADR 0002 accepts: every scrolled frame repaints the
    /// Viewport-sized Canvas. The hitch/frame-time metric is the gate; the
    /// trailing keystroke proves the app is still responsive afterwards.
    @MainActor
    func testFlingScrollingALargeDocumentStaysSmooth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paragraphs", "2000"]
        app.launch()

        let editor = editorElement(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            editor.swipeUp(velocity: .fast)
            editor.swipeUp(velocity: .fast)
            editor.swipeDown(velocity: .fast)
        }

        editor.tap()
        sleep(2)
        let start = Date()
        app.typeText("a")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "typing after a fling must stay responsive")
    }

}
