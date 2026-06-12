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
        let view = ProseView(document: Self.document)
        // Focus once on launch so the system caret is visible immediately.
        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: ProseView, context: Context) {
        // Reassigning `document` rebuilds EditorState, discarding the user's
        // edits and selection — the sample document is set once in makeUIView.
    }

    private static let document: Document = {
        // -paragraphs N loads a large synthetic document instead, for
        // exercising editing performance at document scale (used by the
        // ProseExampleUITests live-keyboard test).
        if let index = CommandLine.arguments.firstIndex(of: "-paragraphs"),
           CommandLine.arguments.indices.contains(index + 1),
           let count = Int(CommandLine.arguments[index + 1]) {
            let sentence = "The quick brown fox jumps over the lazy dog near the quiet river bank. "
            let body = String(repeating: sentence, count: 3)
            return Document(.doc((1...count).map { n in
                .paragraph([.text("Paragraph \(n). " + body)])
            }))
        }
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
