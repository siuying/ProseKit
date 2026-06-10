import XCTest
import CoreGraphics
@testable import ProseEditor
@testable import ProseModel

final class LayoutTests: XCTestCase {
    func testLayoutCreatesOneLeafBoxPerLeafBlockAndStacksThemVertically() throws {
        let document = Document(.doc([
            .heading(level: 1, [.text("Hello")]),
            .paragraph([.text("world")]),
        ]))

        let layout = try LayoutEngine(schema: .slice1).layout(document, width: 320)

        XCTAssertEqual(layout.children.count, 2)
        XCTAssertEqual(layout.children.map(\.kind), [.leafBlock, .leafBlock])
        XCTAssertEqual(layout.children.map(\.node.type), ["heading", "paragraph"])
        XCTAssertGreaterThan(layout.children[1].frame.minY, layout.children[0].frame.minY)
        XCTAssertGreaterThan(layout.children[0].lineFragments[0].typographicHeight, layout.children[1].lineFragments[0].typographicHeight)
    }
}
