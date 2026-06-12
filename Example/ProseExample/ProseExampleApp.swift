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
            } else if CommandLine.arguments.contains("-simple") {
                // Deep-link straight to the Simple Editor for screenshots / review.
                NavigationStack {
                    SimpleEditorScreen(demo: Demo.all.first { $0.id == "simple" }!)
                }
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
            id: "simple",
            title: "Simple Editor",
            subtitle: "Tiptap-parity formatting bar: headings, every inline mark, highlight, links, and alignment",
            icon: "textformat"
        ),
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
        case "simple": return .simpleEditor
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
                if demo.id == "simple" {
                    SimpleEditorScreen(demo: demo)
                } else {
                    DemoEditorScreen(demo: demo)
                }
            }
        }
    }
}

// MARK: - Editor screen

private struct DemoEditorScreen: View {
    let demo: Demo
    @StateObject private var editor = EditorProxy()

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

// MARK: - Simple Editor (Tiptap-parity formatting bar)

private struct SimpleEditorScreen: View {
    let demo: Demo
    @StateObject private var editor = EditorProxy()

    var body: some View {
        SimpleEditorView(document: demo.makeDocument(), editor: editor)
            .ignoresSafeArea(.keyboard)
            .navigationTitle(demo.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Hosts a ProseView whose formatting toolbar is attached as the keyboard's
/// `inputAccessoryView`, so it floats above the keyboard like a real editor.
private struct SimpleEditorView: UIViewRepresentable {
    let document: Document
    let editor: EditorProxy

    func makeUIView(context: Context) -> ProseView {
        let view = ProseView(document: document)
        editor.bind(view)

        let host = UIHostingController(rootView: SimpleEditorToolbar(editor: editor))
        host.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 52)
        host.view.autoresizingMask = .flexibleWidth
        host.sizingOptions = .intrinsicContentSize
        context.coordinator.toolbarHost = host
        view.setInputAccessoryView(host.view)

        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: ProseView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var toolbarHost: UIHostingController<SimpleEditorToolbar>?
    }
}

private struct SimpleEditorToolbar: View {
    @ObservedObject var editor: EditorProxy

    // The default highlight swatches (mirrors HighlightColor's palette).
    private let swatches = ["#ffd54f", "#ff8a80", "#80d8ff", "#ccff90", "#ea80fc"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                blockMenu

                Divider().frame(height: 24)

                mark("bold", "Bold")
                mark("italic", "Italic")
                mark("underline", "Underline")
                mark("strike", "Strikethrough")
                mark("code", "Inline code")
                mark("superscript", "Superscript")
                mark("subscript", "Subscript")

                Divider().frame(height: 24)

                highlightMenu
                Button { editor.view?.setLink("https://example.com") } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 24)

                align("left", "text.alignleft")
                align("center", "text.aligncenter")
                align("right", "text.alignright")
                align("justify", "text.justify")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        // Re-read active state whenever the editor reports a change.
        .id(editor.revision)
    }

    private func mark(_ type: String, _ label: String) -> some View {
        Button {
            editor.toggle(type)
        } label: {
            Image(systemName: symbol(for: type))
        }
        .buttonStyle(.bordered)
        .tint(editor.isActive(type) ? .accentColor : .secondary)
        .accessibilityLabel(label)
    }

    private func align(_ value: String, _ symbol: String) -> some View {
        Button { editor.view?.setTextAlign(value) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    private var blockMenu: some View {
        Menu {
            Button("Paragraph") { editor.view?.setBlockType(headingLevel: nil) }
            ForEach(1...4, id: \.self) { level in
                Button("Heading \(level)") { editor.view?.setBlockType(headingLevel: level) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(blockLabel).font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var highlightMenu: some View {
        Menu {
            ForEach(swatches, id: \.self) { hex in
                Button(hex) { editor.view?.toggleHighlight(hex) }
            }
        } label: {
            Image(systemName: "highlighter")
                .frame(height: 30)
                .padding(.horizontal, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var blockLabel: String {
        if let level = editor.headingLevel { return "H\(level)" }
        return "Paragraph"
    }

    private func symbol(for type: String) -> String {
        switch type {
        case "bold": return "bold"
        case "italic": return "italic"
        case "underline": return "underline"
        case "strike": return "strikethrough"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "superscript": return "textformat.superscript"
        case "subscript": return "textformat.subscript"
        default: return "questionmark"
        }
    }
}

/// Lets SwiftUI toolbar buttons reach the underlying ProseView and observe its
/// active-state changes.
@MainActor private final class EditorProxy: ObservableObject {
    weak var view: ProseView?
    @Published private(set) var revision = 0

    func bind(_ view: ProseView) {
        self.view = view
        view.onStateChange = { [weak self] in self?.revision &+= 1 }
    }

    func toggle(_ type: String) {
        switch type {
        case "bold": view?.toggleBold()
        case "italic": view?.toggleItalic()
        case "underline": view?.toggleUnderline()
        case "strike": view?.toggleStrike()
        case "code": view?.toggleCode()
        case "superscript": view?.toggleSuperscript()
        case "subscript": view?.toggleSubscript()
        default: break
        }
    }

    func isActive(_ type: String) -> Bool {
        view?.isActive(Mark(type: type)) ?? false
    }

    var headingLevel: Int? { view?.activeHeadingLevel }
}

private struct ProseEditorView: UIViewRepresentable {
    let document: Document
    var proxy: EditorProxy?

    func makeUIView(context: Context) -> ProseView {
        let view = ProseView(document: document)
        proxy?.bind(view)
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

    fileprivate static let simpleEditor = Document(.doc([
        .heading(level: 1, [.text("Simple Editor")]),
        .paragraph([
            .text("A Tiptap-parity formatting bar over the CoreText engine. Select text and tap the bar below to apply "),
            .text("bold", marks: [.bold]),
            .text(", "),
            .text("italic", marks: [.italic]),
            .text(", "),
            .text("underline", marks: [Mark(type: "underline")]),
            .text(", "),
            .text("strikethrough", marks: [Mark(type: "strike")]),
            .text(", and "),
            .text("inline code", marks: [.code]),
            .text("."),
        ]),
        .heading(level: 2, [.text("Highlight, links, and scripts")]),
        .paragraph([
            .text("Highlight runs in "),
            .text("any colour", marks: [Mark(type: "highlight", attrs: ["color": .string("#ffd54f")])]),
            .text(" — even "),
            .text("a second one", marks: [Mark(type: "highlight", attrs: ["color": .string("#80d8ff")])]),
            .text(". Links render as "),
            .text("example.com", marks: [Mark(type: "link", attrs: ["href": .string("https://example.com")])]),
            .text(". Water is H"),
            .text("2", marks: [Mark(type: "subscript")]),
            .text("O; Einstein wrote E = mc"),
            .text("2", marks: [Mark(type: "superscript")]),
            .text("."),
        ]),
        Node(
            type: "paragraph",
            attrs: ["textAlign": .string("center")],
            content: [.text("This paragraph is centered. Use the alignment buttons to set left, center, right, or justify.")]
        ),
        .heading(level: 3, [.text("Headings are level-aware")]),
        .heading(level: 4, [.text("H4 is smaller than H1")]),
        .paragraph([.text("Pick a block type from the leftmost menu, then keep typing.")]),
    ]))

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
