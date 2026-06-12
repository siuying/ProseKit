import ProseEditor
import ProseModel
import SwiftUI

@main
struct ProseExampleApp: App {
    var body: some Scene {
        WindowGroup {
            // -paragraphs N skips the demo list and shows a bare editor on a
            // large synthetic document, for exercising editing performance at
            // document scale (used by the ProseExampleUITests live-keyboard
            // and fling-scrolling tests, which expect the editor at root).
            if let count = Self.syntheticParagraphCount {
                ProseEditorView(document: .synthetic(paragraphs: count))
                    .ignoresSafeArea(.keyboard)
            } else {
                DemoListView()
            }
        }
    }

    private static let syntheticParagraphCount: Int? = {
        guard let index = CommandLine.arguments.firstIndex(of: "-paragraphs"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return Int(CommandLine.arguments[index + 1])
    }()
}

// MARK: - Demo catalog

private struct Demo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var showsFormattingBar = false

    static let all: [Demo] = [
        Demo(
            id: "basics",
            title: "Rich Text Basics",
            subtitle: "Headings, paragraphs, and inline marks rendered by the CoreText engine",
            icon: "doc.richtext"
        ),
        Demo(
            id: "formatting",
            title: "Marks & Formatting",
            subtitle: "Toggle bold, italic, code, and headings from a toolbar or ⌘B/⌘I",
            icon: "bold.italic.underline",
            showsFormattingBar: true
        ),
        Demo(
            id: "selection",
            title: "Selection & Autoscroll",
            subtitle: "System selection handles, edit menu, and drag-to-edge autoscroll",
            icon: "text.cursor"
        ),
        Demo(
            id: "structure",
            title: "Structural Editing",
            subtitle: "Return splits a block, Backspace at the start joins it with the previous one",
            icon: "rectangle.split.3x1"
        ),
        Demo(
            id: "large",
            title: "Large Document",
            subtitle: "2,000 paragraphs: fling scrolling, keyboard avoidance, responsive typing",
            icon: "scroll"
        ),
    ]

    func makeDocument() -> Document {
        switch id {
        case "basics": return .basics
        case "formatting": return .formatting
        case "selection": return .selection
        case "structure": return .structure
        case "large": return .synthetic(paragraphs: 2000)
        default: return Document(.doc([]))
        }
    }
}

private struct DemoListView: View {
    var body: some View {
        NavigationStack {
            List(Demo.all) { demo in
                NavigationLink(value: demo) {
                    HStack(spacing: 14) {
                        Image(systemName: demo.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(demo.title)
                                .font(.headline)
                            Text(demo.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Prose Demos")
            .navigationDestination(for: Demo.self) { demo in
                DemoEditorScreen(demo: demo)
            }
        }
    }
}

// MARK: - Editor screen

private struct DemoEditorScreen: View {
    let demo: Demo
    @State private var editor = EditorProxy()

    var body: some View {
        ProseEditorView(document: demo.makeDocument(), proxy: editor)
            .ignoresSafeArea(.keyboard)
            .navigationTitle(demo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if demo.showsFormattingBar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Heading", systemImage: "textformat.size") { editor.view?.toggleHeading() }
                        Button("Bold", systemImage: "bold") { editor.view?.toggleBold() }
                        Button("Italic", systemImage: "italic") { editor.view?.toggleItalic() }
                        Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { editor.view?.toggleCode() }
                    }
                }
            }
    }
}

/// Lets SwiftUI toolbar buttons reach the underlying ProseView.
private final class EditorProxy {
    weak var view: ProseView?
}

private struct ProseEditorView: UIViewRepresentable {
    let document: Document
    var proxy: EditorProxy?

    func makeUIView(context: Context) -> ProseView {
        let view = ProseView(document: document)
        proxy?.view = view
        // Focus once on push so the system caret is visible immediately.
        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: ProseView, context: Context) {
        // Reassigning `document` rebuilds EditorState, discarding the user's
        // edits and selection — each demo document is set once in makeUIView.
    }
}

// MARK: - Demo documents

extension Document {
    static func synthetic(paragraphs count: Int) -> Document {
        let sentence = "The quick brown fox jumps over the lazy dog near the quiet river bank. "
        let body = String(repeating: sentence, count: 3)
        return Document(.doc((1...count).map { n in
            .paragraph([.text("Paragraph \(n). " + body)])
        }))
    }

    fileprivate static let basics = Document(.doc([
        .heading(level: 1, [.text("Rich Text Basics")]),
        .paragraph([
            .text("This document is a tree of block nodes — headings and paragraphs — "),
            .text("typeset by a custom CoreText layout engine."),
        ]),
        .heading(level: 2, [.text("Inline marks")]),
        .paragraph([
            .text("Text carries marks: "),
            .text("bold", marks: [.bold]),
            .text(", "),
            .text("italic", marks: [.italic]),
            .text(", and "),
            .text("code", marks: [.code]),
            .text(". Marks compose, so "),
            .text("bold italic", marks: [.bold, .italic]),
            .text(" works too."),
        ]),
        .paragraph([
            .text("Tap anywhere and start typing — every edit is an invertible "),
            .text("step applied to an immutable document."),
        ]),
    ]))

    fileprivate static let formatting = Document(.doc([
        .heading(level: 1, [.text("Marks & Formatting")]),
        .paragraph([
            .text("Select some text, then use the toolbar buttons above to toggle "),
            .text("bold", marks: [.bold]),
            .text(", "),
            .text("italic", marks: [.italic]),
            .text(", or "),
            .text("code", marks: [.code]),
            .text("."),
        ]),
        .paragraph([
            .text("The heading button turns the current paragraph into a heading and back."),
        ]),
        .paragraph([
            .text("With a hardware keyboard, "),
            .text("⌘B", marks: [.code]),
            .text(" and "),
            .text("⌘I", marks: [.code]),
            .text(" toggle bold and italic on the selection."),
        ]),
        .paragraph([.text("Try formatting this sentence with everything at once.")]),
    ]))

    fileprivate static let selection = Document(.doc(
        [
            .heading(level: 1, [.text("Selection & Autoscroll")]),
            .paragraph([
                .text("Double-tap a word to select it, then drag a selection handle. "),
                .text("Selection is driven by the system's "),
                .text("UITextInteraction", marks: [.code]),
                .text(", so loupe, handles, and the edit menu all behave natively."),
            ]),
            .paragraph([
                .text("Drag a handle to the top or bottom edge of the screen and hold it "),
                .text("there — the editor autoscrolls so the selection can keep growing "),
                .text("past the visible page. The paragraphs below give it room to run."),
            ]),
            .paragraph([
                .text("Copy, cut, and paste from the edit menu work on any selection."),
            ]),
        ] + (1...40).map { n in
            .paragraph([.text("Filler paragraph \(n). Keep dragging the selection handle toward the screen edge and watch the document scroll underneath it.")])
        }
    ))

    fileprivate static let structure = Document(.doc([
        .heading(level: 1, [.text("Structural Editing")]),
        .paragraph([
            .text("Press "),
            .text("Return", marks: [.code]),
            .text(" in the middle of this paragraph and it splits into two block "),
            .text("nodes at the caret."),
        ]),
        .paragraph([
            .text("Press "),
            .text("Backspace", marks: [.code]),
            .text(" at the very start of this paragraph and it joins back into "),
            .text("the previous one."),
        ]),
        .paragraph([
            .text("Splitting and joining are commands that produce document steps, "),
            .text("so the layout only re-typesets the blocks the edit touched."),
        ]),
    ]))
}
