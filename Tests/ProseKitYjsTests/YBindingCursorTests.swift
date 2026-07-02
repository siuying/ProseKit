import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

/// The Binding's Position ⇄ Y relative-position mapping — the anchoring that
/// lets awareness cursors survive concurrent edits and cross the wire to
/// y-prosemirror peers (plan Phase 1b, contract §Positions).
@MainActor
final class YBindingCursorTests: XCTestCase {
    private func makeBoundCore(_ text: String) -> (core: EditorCore, binding: YBinding, doc: YDoc) {
        let core = EditorCore(document: Document(.doc([.paragraph(text.isEmpty ? [] : [.text(text)])])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        return (core, binding, doc)
    }

    func testCaretPositionRoundTripsThroughARelativePosition() throws {
        let (_, binding, _) = makeBoundCore("hello")

        // Caret after "h": root token at 0, paragraph opens at 1, text starts at 2.
        let relative = try XCTUnwrap(binding.relativePosition(for: 3))

        XCTAssertEqual(binding.position(for: relative), 3)
    }

    func testAnchoredPositionTracksARemoteInsertBeforeIt() async throws {
        let (core, binding, doc) = makeBoundCore("hello")
        let relative = try XCTUnwrap(binding.relativePosition(for: 3))

        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        try doc.write(origin: "remote-peer") { transaction in
            guard case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
                  case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
            else { return XCTFail("expected paragraph > text") }
            try transaction.insert("XX", into: textNode, at: 0)
        }
        for _ in 0..<10 where core.document.plainText != "XXhello" {
            await Task.yield()
        }

        XCTAssertEqual(core.document.plainText, "XXhello")
        XCTAssertEqual(binding.position(for: relative), 5)
    }

    func testCaretInALaterBlockAnchorsIntoThatBlocksTextNode() throws {
        let core = EditorCore(document: Document(.doc([
            .paragraph([.text("one")]),
            .paragraph([.text("two")]),
        ])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        // Second paragraph opens at 6 ("one" + two tokens); caret after "tw" is 9.
        let relative = try XCTUnwrap(binding.relativePosition(for: 9))

        XCTAssertEqual(binding.position(for: relative), 9)
    }

    func testCaretInAPeerAuthoredEmptyParagraphAnchorsToTheElement() async throws {
        // y-prosemirror creates an empty paragraph with no text child; a caret
        // there has no text node to anchor into.
        let (core, binding, doc) = makeBoundCore("hello")

        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        try doc.write(origin: "remote-peer") { transaction in
            _ = try transaction.insertElement(named: "paragraph", into: fragment, at: 1)
        }
        for _ in 0..<10 where core.document.root.content.count != 2 {
            await Task.yield()
        }
        XCTAssertEqual(core.document.root.content.count, 2)

        // The empty paragraph opens at 8 ("hello" + root/paragraph tokens);
        // the caret inside it is 9.
        let relative = try XCTUnwrap(binding.relativePosition(for: 9))

        XCTAssertEqual(binding.position(for: relative), 9)
    }

    func testWebPeersDocumentEndCursorResolvesToTheDocumentEnd() throws {
        // y-prosemirror anchors a document-end cursor to the root fragment by
        // name; the JSON carries explicit nulls for the unused scopes.
        let (core, binding, _) = makeBoundCore("hello")

        let json = try JSONSerialization.data(withJSONObject: [
            "type": NSNull(), "tname": YBinding.defaultFragmentName, "item": NSNull(), "assoc": 0,
        ])
        let relative = try YRelativePosition(json: json)

        XCTAssertEqual(binding.position(for: relative), core.document.endPosition)
    }
}
