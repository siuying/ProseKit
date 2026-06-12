#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Pins draw-rect culling (issue 05): an edited view must render exactly
/// like a freshly created view of the same document — culling and dirty
/// rects may never leave stale or missing pixels.
@MainActor
final class RenderingTests: XCTestCase {
    private static let size = CGSize(width: 390, height: 844)

    private func makeView(_ document: Document) -> ProseView {
        let view = ProseView(document: document)
        view.frame = CGRect(origin: .zero, size: Self.size)
        view.layoutIfNeeded()
        return view
    }

    /// Renders deterministically at scale 1 so images are byte-comparable.
    private func render(_ view: ProseView) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: Self.size, format: format)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        return image.pngData() ?? Data()
    }

    private func assertRendersLikeFreshView(_ view: ProseView, _ message: String) {
        let fresh = makeView(view.document)
        // Edits reveal the caret, so the edited view may have scrolled; the
        // comparison is between Viewports at the same content position.
        fresh.contentOffset = view.contentOffset
        fresh.layoutIfNeeded()
        XCTAssertEqual(render(view), render(fresh), message)
    }

    private var fixture: Document {
        Document(.doc(TheLastQuestion.paragraphs.prefix(12).map { .paragraph([.text($0)]) }))
    }

    func testTypingMidBlockRendersLikeFreshView() {
        let view = makeView(fixture)
        // Middle of the second on-screen block.
        guard let textStart = view.document.position(ofTextInBlockAt: 1) else { return XCTFail("fixture") }
        view.selectedTextRange = ProseTextRange(anchor: textStart + 5, head: textStart + 5)
        view.insertText("hello")
        assertRendersLikeFreshView(view, "insert that grows a block must repaint everything it moved")
    }

    func testParagraphSplitRendersLikeFreshView() {
        let view = makeView(fixture)
        guard let textStart = view.document.position(ofTextInBlockAt: 1) else { return XCTFail("fixture") }
        view.selectedTextRange = ProseTextRange(anchor: textStart + 5, head: textStart + 5)
        view.insertText("\n")
        assertRendersLikeFreshView(view, "split moves every block below; all of it must repaint")
    }

    func testJoinBackwardRendersLikeFreshView() {
        let view = makeView(fixture)
        guard let textStart = view.document.position(ofTextInBlockAt: 2) else { return XCTFail("fixture") }
        view.selectedTextRange = ProseTextRange(anchor: textStart, head: textStart)
        view.deleteBackward()
        assertRendersLikeFreshView(view, "join moves every block below; all of it must repaint")
    }

    /// Issue 07 removed the layout store's per-block content comparison; the
    /// Changed Range alone decides reuse. Typing at the document start shifts
    /// every block below (the all-tail reuse path); these renders catch any
    /// stale geometry that trust could let through.
    func testTypingAtDocumentStartRendersLikeFreshView() {
        let view = makeView(fixture)
        view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
        view.insertText("hello")
        assertRendersLikeFreshView(view, "edit at the start must shift and repaint everything below")
    }

    /// Typing at the document end reuses every block above untouched (the
    /// all-prefix reuse path).
    func testTypingAtDocumentEndRendersLikeFreshView() {
        let view = makeView(fixture)
        view.insertText("hello")
        assertRendersLikeFreshView(view, "edit at the end must leave every block above intact")
    }

    func testDeleteShrinkingAVisibleBlockRendersLikeFreshView() {
        let view = makeView(fixture)
        guard let textStart = view.document.position(ofTextInBlockAt: 1),
              let count = view.document.textCount(ofBlockAt: 1) else { return XCTFail("fixture") }
        let blockEnd = textStart + count
        view.selectedTextRange = ProseTextRange(anchor: blockEnd, head: blockEnd)
        // Enough deletes to drop a line from the visible block, moving
        // every block below it up.
        for _ in 0..<60 { view.deleteBackward() }
        assertRendersLikeFreshView(view, "shrinking a visible block must repaint the vacated region")
    }

    /// Drawing a sub-rect must produce the same pixels inside that rect as
    /// drawing the full bounds — culling may skip work, never change output.
    func testPartialRectDrawMatchesFullDrawWithinTheRect() {
        let view = makeView(fixture)
        guard let block = blockFrame(of: view, at: 2) else { return XCTFail("fixture") }
        let subRect = block.insetBy(dx: 0, dy: -2)

        func drawImage(_ rect: CGRect) -> CGImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: Self.size, format: format)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: Self.size))
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect)
                // The Canvas's draw path; at contentOffset zero its local
                // space coincides with content space.
                view.drawCanvas(rect, in: context.cgContext)
                context.cgContext.restoreGState()
            }
            return image.cgImage
        }

        guard let partial = drawImage(subRect)?.cropping(to: subRect),
              let full = drawImage(CGRect(origin: .zero, size: Self.size))?.cropping(to: subRect) else {
            return XCTFail("rendering failed")
        }
        XCTAssertEqual(
            UIImage(cgImage: partial).pngData(),
            UIImage(cgImage: full).pngData(),
            "culled partial draw diverged from full draw inside the dirty rect"
        )
    }

    private func blockFrame(of view: ProseView, at index: Int) -> CGRect? {
        var store = IncrementalLayoutStore(schema: .slice1, width: Self.size.width)
        guard let layout = try? store.layout(view.document),
              layout.children.indices.contains(index) else { return nil }
        return layout.children[index].frame
    }

    // MARK: - editDirtyRect unit tests

    private func layoutPair(
        _ before: Document,
        edit: (inout EditorState) throws -> Void
    ) throws -> (previous: LayoutBox, current: LayoutBox, changedRange: Range<Position>) {
        var store = IncrementalLayoutStore(schema: .slice1, width: Self.size.width)
        let previous = try store.layout(before)
        var state = EditorState(document: before)
        try edit(&state)
        guard let changedRange = state.lastTransaction?.changedRange else {
            throw XCTSkip("edit produced no transaction")
        }
        let current = try store.layout(state.document, changedRange: changedRange)
        return (previous, current, changedRange)
    }

    func testDirtyRectForPlainInsertCoversOnlyTheEditedBlockStrip() throws {
        let document = fixture
        let bounds = CGRect(origin: .zero, size: Self.size)
        guard let textStart = document.position(ofTextInBlockAt: 1) else { return XCTFail("fixture") }
        let (previous, current, changedRange) = try layoutPair(document) { state in
            // Replace one character so the block's height cannot change.
            try state.dispatch(Transaction(
                steps: [ReplaceStep(from: textStart + 1, to: textStart + 2, insertText: "x")],
                selection: TextSelection(anchor: textStart + 2, head: textStart + 2),
                origin: .local
            ))
        }
        XCTAssertEqual(previous.frame.height, current.frame.height, "fixture edit must not reflow")

        let dirty = ProseView.editDirtyRect(
            from: previous, to: current, changedRange: changedRange, fallback: bounds
        )
        let editedBlock = current.children[1].frame
        XCTAssertTrue(dirty.contains(editedBlock), "dirty rect must cover the edited block")
        XCTAssertLessThan(dirty.height, current.frame.height / 2, "single-block edit must not repaint the document")
        XCTAssertGreaterThan(dirty.minY, 0, "blocks above the edit are clean")
    }

    func testDirtyRectForSplitExtendsToTheTallerLayoutBottom() throws {
        let document = fixture
        let bounds = CGRect(origin: .zero, size: Self.size)
        guard let textStart = document.position(ofTextInBlockAt: 1) else { return XCTFail("fixture") }
        let (previous, current, changedRange) = try layoutPair(document) { state in
            let (split, selection, range) = try state.document.splitBlock(at: textStart + 5)
            state.replaceDocument(split, selection: selection, changedRange: range)
        }
        let dirty = ProseView.editDirtyRect(
            from: previous, to: current, changedRange: changedRange, fallback: bounds
        )
        let editedBlockTop = current.children[1].frame.minY
        XCTAssertLessThanOrEqual(dirty.minY, editedBlockTop)
        XCTAssertGreaterThanOrEqual(
            dirty.maxY,
            max(previous.frame.maxY, current.frame.maxY),
            "split moves every block below; dirty rect must reach the taller bottom"
        )
        XCTAssertGreaterThan(dirty.minY, 0, "blocks above the split are clean")
    }

    func testDirtyRectWithoutChangedRangeFallsBackToFullBounds() {
        let bounds = CGRect(origin: .zero, size: Self.size)
        XCTAssertEqual(
            ProseView.editDirtyRect(from: nil, to: nil, changedRange: nil, fallback: bounds),
            bounds
        )
    }
}
#endif
