import XCTest
@testable import ProseModel

final class SchemaTests: XCTestCase {
    func testSchemaRejectsMarksOnBlockNodes() {
        let document = Document(.doc([
            Node(type: "paragraph", content: [.text("marked block")], marks: [.bold]),
        ]))

        XCTAssertThrowsError(try Schema.slice1.validate(document)) { error in
            XCTAssertTrue(String(describing: error).contains("marks are only allowed on text nodes"))
        }
    }

    func testSchemaRejectsDisallowedChildren() {
        let document = Document(.doc([
            .paragraph([.heading(level: 1, [.text("nested")])]),
        ]))

        XCTAssertThrowsError(try Schema.slice1.validate(document)) { error in
            XCTAssertTrue(String(describing: error).contains("paragraph may only contain text"))
        }
    }
}
