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
