import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

/// Proves the `ProseKitYjs` target builds and links SwiftYrs, and that it can
/// reach the `EditorCore` collaboration seam it will drive in later slices.
@MainActor
final class ProseKitYjsTests: XCTestCase {
    func testLinksSwiftYrs() {
        let doc: YDoc = ProseKitYjs.makeDocument()
        XCTAssertNotNil(doc)
    }

    func testCanObserveEditorCoreSeam() throws {
        // The Binding (a later slice) drives convergence through this seam; the
        // scaffold only proves it is reachable from ProseKitYjs.
        let core = EditorCore(document: Document(.doc([.paragraph([.text("hi")])])))
        core.setSelection(TextSelection(anchor: 4, head: 4))

        var origins: [Origin] = []
        core.didApplyTransaction = { origins.append($0.origin) }
        try core.insertText("!")

        XCTAssertEqual(origins, [.local])
    }
}
