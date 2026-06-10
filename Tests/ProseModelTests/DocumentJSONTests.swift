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
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
