import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

@MainActor
final class ProseKitYjsTests: XCTestCase {
    func testLinksSwiftYrs() {
        let doc: YDoc = ProseKitYjs.makeDocument()
        XCTAssertNotNil(doc)
    }

    func testCanObserveEditorCoreSeam() throws {
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi")])])))
        core.setSelection(TextSelection(anchor: 4, head: 4))

        var origins: [Origin] = []
        core.didApplyTransaction = { origins.append($0.origin) }
        try core.insertText("!")

        XCTAssertEqual(origins, [.local])
    }
}
