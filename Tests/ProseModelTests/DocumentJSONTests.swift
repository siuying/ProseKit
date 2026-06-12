import XCTest
@testable import ProseModel

final class DocumentJSONTests: XCTestCase {
    func testDocumentRoundTripsProseMirrorShapedJSON() throws {
        let json = """
        {
          "type": "doc",
          "content": [
            {
              "type": "heading",
              "attrs": { "level": 1 },
              "content": [{ "type": "text", "text": "Hello" }]
            },
            {
              "type": "paragraph",
              "content": [{ "type": "text", "text": "world" }]
            }
          ]
        }
        """.data(using: .utf8)!

        let document = try JSONDecoder().decode(Document.self, from: json)

        try Schema.slice1.validate(document)

        let encoded = try JSONEncoder.sorted.encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: encoded)
        XCTAssertEqual(decoded, document)
    }

    func testUnknownMarksRoundTripVerbatim() throws {
        let json = """
        {
          "type": "doc",
          "content": [
            {
              "type": "paragraph",
              "content": [{
                "type": "text",
                "text": "Hello",
                "marks": [
                  { "type": "xyzzy" },
                  { "type": "frobnicate", "attrs": { "color": "#ffd54f" } }
                ]
              }]
            }
          ]
        }
        """.data(using: .utf8)!

        let document = try JSONDecoder().decode(Document.self, from: json)

        // ADR 0006: a document carrying marks outside our supported set must
        // validate (preserved, not rejected)...
        try Schema.slice1.validate(document)

        // ...and re-export byte-faithfully, attrs included (ADR 0005).
        let encoded = try JSONEncoder.sorted.encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: encoded)
        XCTAssertEqual(decoded, document)

        let marks = document.root.content[0].content[0].marks
        XCTAssertEqual(marks.map(\.type), ["xyzzy", "frobnicate"])
        XCTAssertEqual(marks[1].attrs["color"], .string("#ffd54f"))
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
