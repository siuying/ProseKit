import XCTest
@testable import ProseEditor
@testable import ProseModel

/// Remote collaborators' selections render as Selection Layer chrome (plan
/// Phase 1b): editor-drawn carets, range highlights, and name labels through
/// the same geometry path as the local caret.
@MainActor
final class RemoteSelectionTests: XCTestCase {
    #if canImport(AppKit)
    private func makeLaidOutView() -> ProseView {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello mac")]),
            .paragraph([.text("second paragraph")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testRemoteCaretsRenderThroughSharedGeometry() throws {
        let view = makeLaidOutView()

        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed, selection: TextSelection(anchor: 4, head: 4)),
        ]

        let chrome = try XCTUnwrap(view.selectionLayer.remoteChrome.first)
        XCTAssertEqual(chrome.caretRect, view.core.caretRect(for: 4))
        XCTAssertEqual(chrome.name, "Ada (Web)")
        XCTAssertEqual(chrome.color, .systemRed)
        XCTAssertTrue(chrome.highlightRects.isEmpty)
    }

    func testRemoteRangeSelectionsRenderHighlightRects() throws {
        let view = makeLaidOutView()
        let selection = TextSelection(anchor: 2, head: 8)

        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed, selection: selection),
        ]

        let chrome = try XCTUnwrap(view.selectionLayer.remoteChrome.first)
        XCTAssertEqual(chrome.highlightRects, view.core.selectionRects(for: selection))
        XCTAssertFalse(chrome.highlightRects.isEmpty)
    }

    func testStaleRemoteSelectionsClampToTheDocument() throws {
        // Awareness states lag edits: a peer's selection can momentarily point
        // past the end of the shrunk document.
        let view = makeLaidOutView()
        let end = view.core.document.endPosition

        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed,
                            selection: TextSelection(anchor: end + 40, head: end + 40)),
        ]

        let chrome = try XCTUnwrap(view.selectionLayer.remoteChrome.first)
        XCTAssertEqual(chrome.caretRect, view.core.caretRect(for: end))
    }

    func testRemoteTransactionsRefreshRemoteChromeGeometry() throws {
        // A binding applies peer edits as remote-Origin Transactions; the
        // chrome must recompute so carets stay pinned to the reflowed text.
        let view = makeLaidOutView()
        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed,
                            selection: TextSelection(anchor: 4, head: 4)),
        ]
        let before = try XCTUnwrap(view.selectionLayer.remoteChrome.first).caretRect

        let step = ReplaceStep(from: 2, to: 2, insertText: "WWWW")
        view.core.applyRemote(Transaction(steps: [step], selection: view.core.selection, origin: .remote))

        let after = try XCTUnwrap(view.selectionLayer.remoteChrome.first).caretRect
        XCTAssertEqual(after, view.core.caretRect(for: 4))
        XCTAssertNotEqual(after, before)
    }
    #endif

    #if canImport(UIKit)
    private func makeLaidOutView() -> ProseView {
        let view = ProseView(document: Document(.doc([
            .paragraph([.text("hello phone")]),
            .paragraph([.text("second paragraph")]),
        ])))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        view.layoutIfNeeded()
        return view
    }

    func testRemoteCaretsRenderInAnEditorOwnedOverlay() throws {
        // The system draws only the local caret (UITextInteraction); remote
        // carets are the editor's own chrome, above the Canvas.
        let view = makeLaidOutView()

        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed, selection: TextSelection(anchor: 4, head: 4)),
        ]

        XCTAssertTrue(view.remoteSelectionLayer.superview === view)
        let canvasIndex = try XCTUnwrap(view.subviews.firstIndex(where: { $0 === view.canvas }))
        let overlayIndex = try XCTUnwrap(view.subviews.firstIndex(where: { $0 === view.remoteSelectionLayer }))
        XCTAssertGreaterThan(overlayIndex, canvasIndex)
        let chrome = try XCTUnwrap(view.remoteSelectionLayer.remoteChrome.first)
        XCTAssertEqual(chrome.caretRect, view.core.caretRect(for: 4))
        XCTAssertEqual(chrome.name, "Ada (Web)")
    }

    func testRemoteTransactionsRefreshTheRemoteOverlay() throws {
        let view = makeLaidOutView()
        view.remoteSelections = [
            RemoteSelection(id: 7, name: "Ada (Web)", color: .systemRed,
                            selection: TextSelection(anchor: 4, head: 4)),
        ]
        let before = try XCTUnwrap(view.remoteSelectionLayer.remoteChrome.first).caretRect

        let step = ReplaceStep(from: 2, to: 2, insertText: "WWWW")
        view.core.applyRemote(Transaction(steps: [step], selection: view.core.selection, origin: .remote))

        let after = try XCTUnwrap(view.remoteSelectionLayer.remoteChrome.first).caretRect
        XCTAssertEqual(after, view.core.caretRect(for: 4))
        XCTAssertNotEqual(after, before)
    }
    #endif
}
