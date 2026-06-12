#if canImport(UIKit)
import UIKit
import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Measures rendering and editing performance of ProseView against UITextView
/// on the same text: one screenful and a many-screen document (The Last
/// Question, see TheLastQuestionFixture).
///
/// Pairs of tests share a name except for the `Prose`/`UITextView` suffix, so
/// the comparison is a matter of reading the two averages off the log.
@MainActor
final class PerformanceTests: XCTestCase {
    /// iPhone-sized viewport; both views get the same frame.
    private static let screenSize = CGSize(width: 390, height: 844)
    private static let keystrokes = 50

    // MARK: - Fixtures

    private func makeDocument(_ paragraphs: [String]) -> Document {
        Document(.doc(paragraphs.map { .paragraph([.text($0)]) }))
    }

    /// Same content styled like Prose's BlockStyle: 17pt system font, 12pt
    /// gaps between paragraphs.
    private func makeAttributedText(_ paragraphs: [String]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 12
        return NSAttributedString(
            string: paragraphs.joined(separator: "\n"),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: UIColor.label,
                .paragraphStyle: style,
            ]
        )
    }

    private func makeProseView(_ document: Document) -> ProseView {
        let view = ProseView(document: document)
        view.frame = CGRect(origin: .zero, size: Self.screenSize)
        return view
    }

    private func makeTextView(_ text: NSAttributedString) -> UITextView {
        let view = UITextView(frame: CGRect(origin: .zero, size: Self.screenSize))
        view.attributedText = text
        return view
    }

    private func renderOneScreen(_ view: UIView) -> UIImage {
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: Self.screenSize)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    // MARK: - Benchmark validity

    /// The rendering benchmarks are only a fair comparison if both views
    /// actually rasterize glyphs when rendered off-screen.
    func testRenderingBenchmarkDrawsGlyphsInBothViews() {
        let prose = renderOneScreen(makeProseView(makeDocument(TheLastQuestion.onePage)))
        let textView = renderOneScreen(makeTextView(makeAttributedText(TheLastQuestion.onePage)))
        XCTAssertTrue(hasDarkPixels(prose), "ProseView rendered a blank screen")
        XCTAssertTrue(hasDarkPixels(textView), "UITextView rendered a blank screen")
    }

    private func hasDarkPixels(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data as Data? else {
            return false
        }
        // Any byte well below white means some glyph ink made it to the bitmap.
        return data.contains { $0 < 128 }
    }

    // MARK: - Initial render (create view, lay out, rasterize one screen)

    func testInitialRenderOnePageProse() {
        let document = makeDocument(TheLastQuestion.onePage)
        measure {
            MainActor.assumeIsolated {
                _ = renderOneScreen(makeProseView(document))
            }
        }
    }

    func testInitialRenderOnePageUITextView() {
        let text = makeAttributedText(TheLastQuestion.onePage)
        measure {
            MainActor.assumeIsolated {
                _ = renderOneScreen(makeTextView(text))
            }
        }
    }

    func testInitialRenderManyPagesProse() {
        let document = makeDocument(TheLastQuestion.manyPages)
        measure {
            MainActor.assumeIsolated {
                _ = renderOneScreen(makeProseView(document))
            }
        }
    }

    func testInitialRenderManyPagesUITextView() {
        let text = makeAttributedText(TheLastQuestion.manyPages)
        measure {
            MainActor.assumeIsolated {
                _ = renderOneScreen(makeTextView(text))
            }
        }
    }

    // MARK: - Full document layout (no rasterization)

    /// ProseView always lays out the whole document; layoutIfNeeded is its
    /// full-layout cost.
    func testFullLayoutManyPagesProse() {
        let document = makeDocument(TheLastQuestion.manyPages)
        measure {
            MainActor.assumeIsolated {
                makeProseView(document).layoutIfNeeded()
            }
        }
    }

    /// UITextView (TextKit 2) lays out lazily; force layout of the entire
    /// document so the work matches the Prose test above.
    func testFullLayoutManyPagesUITextView() {
        let text = makeAttributedText(TheLastQuestion.manyPages)
        measure {
            MainActor.assumeIsolated {
                let view = makeTextView(text)
                view.layoutIfNeeded()
                guard let layoutManager = view.textLayoutManager else {
                    return XCTFail("expected TextKit 2")
                }
                layoutManager.ensureLayout(for: layoutManager.documentRange)
            }
        }
    }

    // MARK: - Typing (one character per keystroke, layout flushed per keystroke)

    private func measureTypingProse(
        _ paragraphs: [String],
        atStart: Bool = false,
        paragraphBreakEvery breakInterval: Int? = nil,
        exerciseInteractionPath: Bool = false
    ) {
        let document = makeDocument(paragraphs)
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            MainActor.assumeIsolated {
                let view = makeProseView(document)
                view.layoutIfNeeded()
                if atStart {
                    view.selectedTextRange = ProseTextRange(anchor: 2, head: 2)
                }
                startMeasuring()
                for index in 0..<Self.keystrokes {
                    if let breakInterval, index > 0, index.isMultiple(of: breakInterval) {
                        view.insertText("\n")
                    } else {
                        view.insertText("x")
                    }
                    if exerciseInteractionPath {
                        exerciseUIKitInteractionPath(on: view)
                    }
                }
                stopMeasuring()
            }
        }
    }

    /// Mirrors what UIKit's keyboard machinery was observed to do around
    /// every live keystroke (instrumented 2026-06-12, see
    /// .scratch/editing-performance/issues/04-live-keyboard-path-stall.md):
    /// read the whole document via text(in:), compute the caret's character
    /// offset from the document start, query caret/selection geometry, step
    /// the caret by one character, and run a layout pass dirtied by the
    /// selection chrome's subview changes.
    private func exerciseUIKitInteractionPath(on view: ProseView) {
        guard let selection = view.selectedTextRange as? ProseTextRange else { return }
        if let wholeDocument = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument) {
            _ = view.text(in: wholeDocument)
        }
        _ = view.offset(from: view.beginningOfDocument, to: selection.end)
        _ = view.caretRect(for: selection.end)
        _ = view.selectionRects(for: ProseTextRange(
            anchor: max(2, selection.head - 1),
            head: selection.head
        ))
        if let moved = view.position(from: selection.end, offset: -1) {
            _ = view.position(from: moved, offset: 1)
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func measureTypingUITextView(_ paragraphs: [String], atStart: Bool = false) {
        let text = makeAttributedText(paragraphs)
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            MainActor.assumeIsolated {
                let view = makeTextView(text)
                view.layoutIfNeeded()
                view.selectedRange = NSRange(location: atStart ? 0 : view.textStorage.length, length: 0)
                startMeasuring()
                for _ in 0..<Self.keystrokes {
                    view.insertText("x")
                    view.layoutIfNeeded()
                }
                stopMeasuring()
            }
        }
    }

    func testTypingAtEndOnePageProse() {
        measureTypingProse(TheLastQuestion.onePage)
    }

    func testTypingAtEndOnePageUITextView() {
        measureTypingUITextView(TheLastQuestion.onePage)
    }

    func testTypingAtEndManyPagesProse() {
        measureTypingProse(TheLastQuestion.manyPages)
    }

    func testTypingWithParagraphBreaksManyPagesProse() {
        measureTypingProse(TheLastQuestion.manyPages, paragraphBreakEvery: 10)
    }

    func testInteractionPathTypingManyPagesProse() {
        measureTypingProse(TheLastQuestion.manyPages, exerciseInteractionPath: true)
    }

    func testTypingAtEndManyPagesUITextView() {
        measureTypingUITextView(TheLastQuestion.manyPages)
    }

    func testTypingAtStartManyPagesProse() {
        measureTypingProse(TheLastQuestion.manyPages, atStart: true)
    }

    func testTypingAtStartManyPagesUITextView() {
        measureTypingUITextView(TheLastQuestion.manyPages, atStart: true)
    }

    // MARK: - Deleting (backspace at document end)

    func testDeleteBackwardManyPagesProse() {
        let document = makeDocument(TheLastQuestion.manyPages)
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            MainActor.assumeIsolated {
                let view = makeProseView(document)
                view.layoutIfNeeded()
                startMeasuring()
                for _ in 0..<Self.keystrokes {
                    view.deleteBackward()
                }
                stopMeasuring()
            }
        }
    }

    func testDeleteBackwardManyPagesUITextView() {
        let text = makeAttributedText(TheLastQuestion.manyPages)
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            MainActor.assumeIsolated {
                let view = makeTextView(text)
                view.layoutIfNeeded()
                view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
                startMeasuring()
                for _ in 0..<Self.keystrokes {
                    view.deleteBackward()
                    view.layoutIfNeeded()
                }
                stopMeasuring()
            }
        }
    }
}
#endif
