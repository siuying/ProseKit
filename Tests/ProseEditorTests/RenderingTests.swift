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

    private func render(_ view: ProseView, croppingTo rect: CGRect) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: Self.size, format: format)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cropped = image.cgImage?.cropping(to: rect.integral) else { return Data() }
        return UIImage(cgImage: cropped).pngData() ?? Data()
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

    func testStrikeAndUnderlineDrawDecorations() {
        let plain = makeView(Document(.doc([.paragraph([.text("Hello world")])])))
        let struck = makeView(Document(.doc([.paragraph([.text("Hello world", marks: [Mark(type: "strike")])])])))
        let underlined = makeView(Document(.doc([.paragraph([.text("Hello world", marks: [Mark(type: "underline")])])])))

        XCTAssertNotEqual(render(plain), render(struck), "strikethrough must be drawn over the run")
        XCTAssertNotEqual(render(plain), render(underlined), "underline must be drawn under the run")
    }

    func testHighlightFillsBackgroundParseOrPlain() {
        func doc(_ marks: [Mark]) -> Document { Document(.doc([.paragraph([.text("Hello world", marks: marks)])])) }
        let plain = makeView(doc([]))
        let yellow = makeView(doc([Mark(type: "highlight", attrs: ["color": .string("#ffd54f")])]))
        let blue = makeView(doc([Mark(type: "highlight", attrs: ["color": .string("#80d8ff")])]))
        let unparseable = makeView(doc([Mark(type: "highlight", attrs: ["color": .string("var(--x)")])]))

        XCTAssertNotEqual(render(plain), render(yellow), "a parseable highlight fills a background")
        XCTAssertNotEqual(render(yellow), render(blue), "multicolor: different colours render differently")
        XCTAssertEqual(render(plain), render(unparseable), "an unparseable colour draws no background")
    }

    func testSuperscriptAndSubscriptRenderDistinctly() {
        func doc(_ marks: [Mark]) -> Document { Document(.doc([.paragraph([.text("x2", marks: marks)])])) }
        let plain = makeView(doc([]))
        let sup = makeView(doc([Mark(type: "superscript")]))
        let sub = makeView(doc([Mark(type: "subscript")]))

        XCTAssertNotEqual(render(plain), render(sup), "superscript must raise/shrink the run")
        XCTAssertNotEqual(render(plain), render(sub), "subscript must lower/shrink the run")
        XCTAssertNotEqual(render(sup), render(sub), "super and subscript render differently")
    }

    func testLinkRendersTintAndUnderlineAndAbsorbsUnderlineMark() {
        func doc(_ marks: [Mark]) -> Document { Document(.doc([.paragraph([.text("Hello world", marks: marks)])])) }
        let plain = makeView(doc([]))
        let link = makeView(doc([Mark(type: "link", attrs: ["href": .string("https://example.com")])]))
        let linkPlusUnderline = makeView(doc([
            Mark(type: "link", attrs: ["href": .string("https://example.com")]),
            Mark(type: "underline"),
        ]))

        XCTAssertNotEqual(render(plain), render(link), "a link must render in tint + underline")
        XCTAssertEqual(render(link), render(linkPlusUnderline), "an extra underline mark on a link is invisible (Q9.6)")
    }

    func testTextAlignShiftsLineOrigins() {
        func doc(_ align: String?) -> Document {
            var attrs: [String: JSONValue] = [:]
            if let align { attrs["textAlign"] = .string(align) }
            return Document(.doc([Node(
                type: "paragraph",
                attrs: attrs,
                content: [.text("Hello world, this is a longer line of text that wraps onto several lines so justify has something to stretch")]
            )]))
        }
        let left = render(makeView(doc(nil)))
        XCTAssertNotEqual(left, render(makeView(doc("center"))), "center shifts line origins")
        XCTAssertNotEqual(left, render(makeView(doc("right"))), "right flushes lines to the trailing edge")
        XCTAssertNotEqual(left, render(makeView(doc("justify"))), "justify stretches all but the last line")
    }

    func testHeadingRenderingIsLevelAware() {
        func headingHeight(_ level: Int) -> CGFloat {
            makeView(Document(.doc([.heading(level: level, [.text("Title")])]))).contentSize.height
        }
        XCTAssertGreaterThan(headingHeight(1), headingHeight(2), "h1 is larger than h2")
        XCTAssertGreaterThan(headingHeight(2), headingHeight(3), "h2 is larger than h3")
        XCTAssertGreaterThan(headingHeight(3), headingHeight(4), "h3 is larger than h4")
    }

    func testCheckedTaskItemFadesAndStrikesText() {
        func view(checked: Bool) -> ProseView {
            makeView(Document(.doc([
                .taskList([.taskItem(checked: checked, [.paragraph([.text("finish this task")])])]),
            ])))
        }
        let unchecked = view(checked: false)
        let checked = view(checked: true)
        let textFrame = unchecked.layoutBox!.children[0].children[0].children[0].frame.insetBy(dx: -2, dy: -2)

        XCTAssertNotEqual(
            render(unchecked, croppingTo: textFrame),
            render(checked, croppingTo: textFrame),
            "checked task items must visually fade and strike the text, not only change the checkbox"
        )
    }

    func testOrderedMarkerOriginStaysInsideContentBounds() {
        let markerX = CanvasView.orderedMarkerOriginX(markerWidth: 32, itemMinX: 0)

        XCTAssertGreaterThanOrEqual(markerX, 0, "ordered markers must not start offscreen and get clipped")
        XCTAssertLessThanOrEqual(markerX + 32, containerIndent(forType: "listItem"), "marker should stay in the indent band")
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
                view.canvas.drawCanvas(rect, in: context.cgContext)
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

        let dirty = CanvasView.editDirtyRect(
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
            state = EditorState(document: state.document, selection: TextSelection(anchor: textStart + 5, head: textStart + 5))
            _ = try Commands.splitBlock().run(in: &state)
        }
        let dirty = CanvasView.editDirtyRect(
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
            CanvasView.editDirtyRect(from: nil, to: nil, changedRange: nil, fallback: bounds),
            bounds
        )
    }
}
#endif
