#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Scroll support: ProseView is a UIScrollView whose contentSize is the laid-out
/// Document; the Viewport moves over the layout, the layout never moves.
@MainActor
final class ScrollingTests: XCTestCase {
    private static let size = CGSize(width: 390, height: 400)

    private func makeView(_ document: Document) -> ProseView {
        let view = ProseView(document: document)
        view.frame = CGRect(origin: .zero, size: Self.size)
        view.layoutIfNeeded()
        return view
    }

    private var tallFixture: Document {
        Document(.doc(TheLastQuestion.paragraphs.prefix(30).map { .paragraph([.text($0)]) }))
    }

    /// Renders the Viewport (what the user sees) at the Canvas's native
    /// contentsScale, so layer bitmaps composite 1:1 with no resampling and
    /// images stay byte-comparable.
    private func renderViewport(_ view: ProseView) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size, format: format)
        let image = renderer.image { context in
            // layer.render(in:) places sublayers at content coordinates and
            // ignores bounds.origin; shift so the image shows the Viewport.
            context.cgContext.translateBy(x: -view.bounds.origin.x, y: -view.bounds.origin.y)
            view.layer.render(in: context.cgContext)
        }
        return image.pngData() ?? Data()
    }

    /// The ground truth for a content slice: the same document laid out in a
    /// view tall enough to never scroll, rendered through a context translated
    /// to the slice. Independent of any scrolling code path.
    private func renderReferenceSlice(of document: Document, at offset: CGPoint) -> Data {
        let full = ProseView(document: document)
        full.frame = CGRect(origin: .zero, size: Self.size)
        full.layoutIfNeeded()
        full.frame = CGRect(x: 0, y: 0, width: Self.size.width, height: max(full.contentSize.height, Self.size.height))
        full.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: Self.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -offset.x, y: -offset.y)
            full.layer.render(in: context.cgContext)
        }
        return image.pngData() ?? Data()
    }

    func testScrolledViewportRendersTheLayoutSliceAtTheContentOffset() {
        // Shorter than tallFixture: the reference view hosts a content-sized
        // Canvas, and past ~16384 physical pixels Core Animation silently
        // drops the layer's resolution, making the reference rasterize
        // differently. (The Viewport-sized Canvas exists to avoid exactly
        // this — ADR 0002.)
        let document = Document(.doc(TheLastQuestion.paragraphs.prefix(10).map { .paragraph([.text($0)]) }))
        let view = makeView(document)
        XCTAssertGreaterThan(view.contentSize.height, 2 * Self.size.height, "fixture must overflow the Viewport")
        XCTAssertLessThan(
            view.contentSize.height * UIScreen.main.scale, 16384,
            "fixture too tall for a faithful content-sized reference render"
        )
        let offset = CGPoint(x: 0, y: 300)

        view.contentOffset = offset
        view.layoutIfNeeded()

        let viewport = renderViewport(view)
        let reference = renderReferenceSlice(of: document, at: offset)
        if viewport != reference {
            try? viewport.write(to: URL(fileURLWithPath: "/tmp/prose-viewport.png"))
            try? reference.write(to: URL(fileURLWithPath: "/tmp/prose-reference.png"))
        }
        XCTAssertEqual(
            viewport,
            reference,
            "the Viewport must show exactly the layout slice at the contentOffset"
        )
    }

    /// Edit invalidation happens in content coordinates while the Canvas sits
    /// at the contentOffset; a wrong conversion leaves stale or missing pixels.
    func testTypingWhileScrolledRendersLikeAFreshScrolledView() {
        let document = Document(.doc(TheLastQuestion.paragraphs.prefix(10).map { .paragraph([.text($0)]) }))
        let view = makeView(document)
        let offset = CGPoint(x: 0, y: 300)
        view.contentOffset = offset
        view.layoutIfNeeded()

        // A caret somewhere inside the visible slice, found like a tap would.
        guard let caret = view.closestPosition(to: CGPoint(x: 10, y: 350)) as? ProseTextPosition else {
            return XCTFail("no position in the visible slice")
        }
        view.selectedTextRange = ProseTextRange(anchor: caret.position, head: caret.position)
        view.insertText("hello\nworld")
        view.layoutIfNeeded()

        XCTAssertEqual(
            renderViewport(view),
            renderReferenceSlice(of: view.document, at: offset),
            "an edit while scrolled must repaint exactly the slice it changed"
        )
    }

    /// The scroll view's coordinate space is content space, so UITextInput
    /// geometry answers in document layout coordinates regardless of where
    /// the Viewport sits (ADR 0002).
    func testTextGeometryIsIndependentOfTheContentOffset() {
        let view = makeView(tallFixture)
        let position = ProseTextPosition(40)
        let range = ProseTextRange(anchor: 10, head: 60)

        let caretBefore = view.caretRect(for: position)
        let rectsBefore = view.selectionRects(for: range).map(\.rect)

        view.contentOffset = CGPoint(x: 0, y: 500)
        view.layoutIfNeeded()

        XCTAssertEqual(view.caretRect(for: position), caretBefore)
        XCTAssertEqual(view.selectionRects(for: range).map(\.rect), rectsBefore)

        // And hit-testing inverts through the same space: a content-space
        // point inside the visible slice resolves to a Position whose caret
        // rect contains it.
        let point = CGPoint(x: 30, y: 620)
        guard let hit = view.closestPosition(to: point) as? ProseTextPosition else {
            return XCTFail("no position at \(point)")
        }
        let hitCaret = view.caretRect(for: hit)
        XCTAssertEqual(hitCaret.midY, point.y, accuracy: hitCaret.height)
    }

    private func visibleRect(of view: ProseView) -> CGRect {
        CGRect(origin: view.contentOffset, size: view.bounds.size)
            .inset(by: view.adjustedContentInset)
    }

    func testTypingBelowTheFoldRevealsTheCaret() {
        let view = makeView(tallFixture)
        let end = view.endOfDocument as! ProseTextPosition
        view.selectedTextRange = ProseTextRange(anchor: end.position, head: end.position)

        view.insertText("x")
        view.layoutIfNeeded()

        let caret = view.caretRect(for: view.selectedTextRange!.end)
        XCTAssertTrue(
            visibleRect(of: view).contains(caret),
            "typing must keep the caret in the Viewport; caret \(caret) vs visible \(visibleRect(of: view))"
        )
    }

    func testArrowKeyCaretMoveBelowTheFoldRevealsTheCaret() {
        let view = makeView(tallFixture)
        let end = view.endOfDocument as! ProseTextPosition
        view.selectedTextRange = ProseTextRange(anchor: end.position, head: end.position)
        XCTAssertEqual(view.contentOffset.y, 0, "programmatic selection must not scroll")

        view.moveCaret(.left, extending: false)
        view.layoutIfNeeded()

        let caret = view.caretRect(for: view.selectedTextRange!.end)
        XCTAssertTrue(
            visibleRect(of: view).contains(caret),
            "keyboard caret moves must reveal the caret; caret \(caret) vs visible \(visibleRect(of: view))"
        )
    }

    /// The host's explicit reveal — the counterpart of "programmatic
    /// selection never scrolls" (UITextView parity).
    func testScrollRangeToVisibleRevealsTheRangeWithMinimalScroll() {
        let view = makeView(tallFixture)
        let end = view.endOfDocument as! ProseTextPosition
        let range = ProseTextRange(anchor: end.position - 5, head: end.position)

        view.scrollRangeToVisible(range)
        view.layoutIfNeeded()

        let rect = view.firstRect(for: range)
        let visible = visibleRect(of: view)
        XCTAssertTrue(visible.contains(rect), "range \(rect) must be inside \(visible)")
        // Minimal scroll: coming from above, the range settles near the
        // bottom edge instead of jumping to the top of the Viewport.
        XCTAssertLessThanOrEqual(visible.maxY - rect.maxY, 40)
    }

    /// UITextView parity: only edits, keyboard caret moves, and explicit
    /// scrollRangeToVisible scroll. Hosts setting selection or document
    /// quietly must not move the Viewport.
    func testProgrammaticSelectionAndDocumentChangesDoNotScroll() {
        let view = makeView(tallFixture)
        view.contentOffset = CGPoint(x: 0, y: 500)
        view.layoutIfNeeded()

        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        XCTAssertEqual(view.contentOffset.y, 500, "programmatic selection must not scroll")

        view.document = tallFixture
        view.layoutIfNeeded()
        XCTAssertEqual(view.contentOffset.y, 500, "assigning a document must not scroll")
    }

    /// Deliberate divergence from UITextView (ADR 0002): caret-follow is
    /// built in, so the keyboard inset must be too — otherwise "reveal the
    /// caret" scrolls it to a spot underneath the keyboard.
    func testKeyboardFrameChangesInsetTheViewportByTheOverlap() {
        let view = makeView(tallFixture) // 390x400 at the screen origin

        // Keyboard covering the bottom 150pt of the view.
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                cgRect: CGRect(x: 0, y: 250, width: 390, height: 600)
            )]
        )
        XCTAssertEqual(view.contentInset.bottom, 150, accuracy: 0.5)
        XCTAssertEqual(view.verticalScrollIndicatorInsets.bottom, 150, accuracy: 0.5)

        // Keyboard dismissed: frame fully below the view.
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                cgRect: CGRect(x: 0, y: 400, width: 390, height: 600)
            )]
        )
        XCTAssertEqual(view.contentInset.bottom, 0, accuracy: 0.5)
    }

    func testKeyboardAdjustmentCanBeOptedOut() {
        let view = makeView(tallFixture)
        view.automaticallyAdjustsForKeyboard = false

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                cgRect: CGRect(x: 0, y: 250, width: 390, height: 600)
            )]
        )
        XCTAssertEqual(view.contentInset.bottom, 0, "host opted out; insets are its job")
    }

    func testLongDocumentIsScrollableToTheLayoutHeight() throws {
        let document = tallFixture
        let view = makeView(document)

        let layoutHeight = try LayoutEngine(schema: .slice1)
            .layout(document, width: Self.size.width).frame.height
        XCTAssertGreaterThan(layoutHeight, view.bounds.height, "fixture must overflow the Viewport")
        XCTAssertEqual(view.contentSize.height, layoutHeight, accuracy: 0.5)
        XCTAssertEqual(view.contentSize.width, Self.size.width, accuracy: 0.5)
    }
}
#endif
