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

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/prose-repro/\(name).png"))
    }

    // TEMP repro: selection highlight after heading toggle
    @MainActor
    func testReproHeadingToggleSelectionHighlight() throws {
        let app = XCUIApplication()
        app.launch()
        app.staticTexts["Marks & Formatting"].tap()
        let editor = editorElement(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        sleep(1)
        // Select a word in the first paragraph.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).doubleTap()
        sleep(1)
        attach(app, "1-selected-before-toggle")
        app.buttons["Heading"].tap()
        sleep(1)
        attach(app, "2-after-heading-toggle")
    }

    // TEMP repro: delete key behaviour in structural editing demo
    @MainActor
    func testReproDeleteKeyJoinsBlocks() throws {
        let app = XCUIApplication()
        app.launch()
        app.staticTexts["Structural Editing"].tap()
        let editor = editorElement(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        sleep(2)
        // Select the first word of the second paragraph; its selection start
        // is the block start, so two deletes exercise selection-delete and
        // then the block join.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.165)).doubleTap()
        sleep(1)
        attach(app, "1-word-selected")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(1)
        attach(app, "2-after-selection-delete")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(1)
        attach(app, "3-after-join-delete")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(1)
        attach(app, "4-after-third-delete")
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
    private func launchTypingBenchmark(_ arguments: [String], prefix: String) -> [TimeInterval] {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
            print("[\(prefix)] \(label): \(String(format: "%.3f", elapsed))s")
            return elapsed
        }

        return [
            timedType("a", label: "first char after focusing"),
            timedType("\n", label: "Return (new line)"),
            timedType("b", label: "first char after Return"),
            timedType("c", label: "second char after Return"),
        ]
    }

    @MainActor
    func testLiveTypingAroundAParagraphBreakStaysResponsive() throws {
        let timings = launchTypingBenchmark(["-paragraphs", "800"], prefix: "live-typing")

        // UITextView on the same 800-paragraph fixture is ~3.9s for first focus,
        // ~3.5s for Return, and ~2.1s steady-state in this XCUITest harness.
        // Keep Prose within that envelope plus simulator variance.
        let budget: TimeInterval = 4.5
        for timing in timings {
            XCTAssertLessThan(timing, budget)
        }
    }

    @MainActor
    func testLiveTypingUITextViewBaseline() throws {
        let timings = launchTypingBenchmark(["-uitextview-paragraphs", "800"], prefix: "uitextview-live-typing")
        for timing in timings {
            XCTAssertLessThan(timing, 5)
        }
    }

    @MainActor
    func testLiveTypingSimpleEditorStaysNearUITextViewBaseline() throws {
        let timings = launchTypingBenchmark(["-simple"], prefix: "simple-live-typing")
        let budget: TimeInterval = 4.5
        for timing in timings {
            XCTAssertLessThan(timing, budget)
        }
    }

    /// The formatting toolbar floats in the keyboard's inputAccessoryView and
    /// re-runs its body on every editor-state change (each keystroke and caret
    /// move bumps the editor's revision). Reintroducing `.id(revision)` would
    /// give the toolbar a fresh identity each time, tearing down and rebuilding
    /// the whole tree (three Menus included) — ~12× costlier per rebuild, the
    /// main-thread hostage that made typing choppy on the simulator.
    ///
    /// XCUITest event synthesis (~0.8s/keystroke) swamps a ~5ms rebuild, so a
    /// wall-clock typing test can't see this. Instead the app runs the real
    /// toolbar through synchronous render passes in-process under
    /// `-benchmark-toolbar` and reports ms/rebuild; this test reads that and
    /// gates it. Measured ~0.4–0.6ms fixed vs ~5ms with `.id`, so the 3ms
    /// budget separates them with healthy margin either way.
    @MainActor
    func testToolbarRebuildStaysCheap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-benchmark-toolbar"]
        app.launch()

        let result = app.staticTexts["toolbar-rebuild-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))

        // The benchmark replaces "running…" with "<ms> ms/rebuild over <n>".
        let deadline = Date().addingTimeInterval(20)
        while result.label.contains("running"), Date() < deadline {
            usleep(100_000)
        }

        let label = result.label
        print("[toolbar-rebuild] \(label)")
        let ms = Double(label.split(separator: " ").first ?? "") ?? .infinity
        XCTAssertLessThan(ms, 3.0, "toolbar rebuild regressed to \(label) — did `.id(revision)` come back?")
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
