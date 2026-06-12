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

    func testSchemaPreservesUnknownMarks() throws {
        let document = Document(.doc([
            .paragraph([.text("highlighted", marks: [Mark(type: "xyzzy")])]),
        ]))

        try Schema.slice1.validate(document)
    }

    // ADR 0006 phasing: unknown *marks* are preserved, but an unknown *node*
    // type still raises a clear load error until Opaque Nodes land (slice 18).
    // Never silently accepted or stripped.
    func testSchemaStillRejectsUnknownNodeTypes() {
        let document = Document(.doc([
            Node(type: "image", attrs: ["src": .string("photo.png")]),
        ]))

        // A hard load error, never silent acceptance or stripping. The exact
        // message is slice 18's concern (Opaque Node rendering); here we only
        // pin that an unsupported node type does not slip through validation.
        XCTAssertThrowsError(try Schema.slice1.validate(document)) { error in
            XCTAssertTrue(error is SchemaError)
        }
    }
}
