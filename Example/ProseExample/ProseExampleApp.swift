import ProseEditor
import ProseModel
import SwiftUI

@main
struct ProseExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ProseDocumentView()
                .ignoresSafeArea(.keyboard)
        }
    }
}

private struct ProseDocumentView: UIViewRepresentable {
    func makeUIView(context: Context) -> ProseView {
        ProseView(document: Self.document)
    }

    func updateUIView(_ uiView: ProseView, context: Context) {
        uiView.document = Self.document
    }

    private static let document: Document = {
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
        return (try? JSONDecoder().decode(Document.self, from: json)) ?? Document(.doc([]))
    }()
}
