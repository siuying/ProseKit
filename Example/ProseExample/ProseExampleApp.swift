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
            } else if let demo = Self.deepLinkedDemo {
                // `-demo <id>` deep-links to one demo for screenshots / review
                // (simctl can't tap to navigate).
                NavigationStack {
                    if demo.id == "simple" {
                        SimpleEditorScreen(demo: demo)
                    } else {
                        DemoEditorScreen(demo: demo)
                    }
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

    private static var deepLinkedDemo: Demo? {
        guard let index = CommandLine.arguments.firstIndex(of: "-demo"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        let id = CommandLine.arguments[index + 1]
        return Demo.all.first { $0.id == id }
    }
}

// MARK: - Demo catalog

private struct Demo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var showsFormattingBar = false
    var makeDocument: () -> Document = { Document(.doc([])) }

    static func == (lhs: Demo, rhs: Demo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let all: [Demo] = [
        Demo(
            id: "simple",
            title: "Simple Editor",
            subtitle: "Tiptap-parity formatting bar: headings, every inline mark, highlight, links, and alignment",
            icon: "textformat",
            makeDocument: { .simpleEditor }
        ),
        Demo(
            id: "basics",
            title: "Rich Text Basics",
            subtitle: "Headings, paragraphs, and inline marks rendered by the CoreText engine",
            icon: "doc.richtext",
            makeDocument: { .basics }
        ),
        Demo(
            id: "formatting",
            title: "Marks & Formatting",
            subtitle: "Toggle bold, italic, code, and headings from a toolbar or ⌘B/⌘I",
            icon: "bold.italic.underline",
            showsFormattingBar: true,
            makeDocument: { .formatting }
        ),
        Demo(
            id: "selection",
            title: "Selection & Autoscroll",
            subtitle: "System selection handles, edit menu, and drag-to-edge autoscroll",
            icon: "text.cursor",
            makeDocument: { .selection }
        ),
        Demo(
            id: "structure",
            title: "Structural Editing",
            subtitle: "Return splits a block, Backspace at the start joins it with the previous one",
            icon: "rectangle.split.3x1",
            makeDocument: { .structure }
        ),
        Demo(
            id: "blockquote",
            title: "Block Nesting",
            subtitle: "A blockquote containing paragraphs — nested container layout with an indent rule",
            icon: "text.quote",
            makeDocument: { .nesting }
        ),
        Demo(
            id: "list",
            title: "Bullet List",
            subtitle: "A bullet list: nested bulletList → listItem → paragraph with disc markers",
            icon: "list.bullet",
            makeDocument: { .bulletList }
        ),
        Demo(
            id: "ordered",
            title: "Ordered List",
            subtitle: "Ordinals derived from sibling index; Tab/Shift-Tab sink and lift to nest",
            icon: "list.number",
            makeDocument: { .orderedList }
        ),
        Demo(
            id: "tasks",
            title: "Task List",
            subtitle: "Checkable items — tap a checkbox to toggle its checked attr",
            icon: "checklist",
            makeDocument: { .taskList }
        ),
        Demo(
            id: "large",
            title: "Large Document",
            subtitle: "2,000 paragraphs: fling scrolling, keyboard avoidance, responsive typing",
            icon: "scroll",
            makeDocument: { .synthetic(paragraphs: 2000) }
        ),
    ]
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
                        Button("Bold", systemImage: "bold") { editor.view?.toggleMark(.bold) }
                        Button("Italic", systemImage: "italic") { editor.view?.toggleMark(.italic) }
                        Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { editor.view?.toggleMark(.code) }
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

    /// One row per inline Mark button: the Mark it toggles, its SF Symbol,
    /// and its accessibility label. The single source for the mark buttons.
    private static let markItems: [(mark: Mark, symbol: String, label: String)] = [
        (.bold, "bold", "Bold"),
        (.italic, "italic", "Italic"),
        (.underline, "underline", "Underline"),
        (.strike, "strikethrough", "Strikethrough"),
        (.code, "chevron.left.forwardslash.chevron.right", "Inline code"),
        (.superscript, "textformat.superscript", "Superscript"),
        (.subscript, "textformat.subscript", "Subscript"),
    ]

    // The default highlight swatches (mirrors HighlightColor's palette).
    private let swatches = ["#ffd54f", "#ff8a80", "#80d8ff", "#ccff90", "#ea80fc"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                blockMenu

                Divider().frame(height: 24)

                ForEach(Self.markItems, id: \.mark) { item in
                    markButton(item.mark, symbol: item.symbol, label: item.label)
                }

                Divider().frame(height: 24)

                highlightMenu
                Button { editor.view?.setLink("https://example.com") } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 24)

                listMenu
                toolButton("increase.indent", "Indent") { editor.view?.sinkListItem() }
                toolButton("decrease.indent", "Outdent") { editor.view?.liftListItem() }
                toolButton("checklist.checked", "Toggle task") { editor.view?.toggleTaskItemChecked() }

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

    private func markButton(_ mark: Mark, symbol: String, label: String) -> some View {
        Button {
            editor.view?.toggleMark(mark)
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.bordered)
        .tint(editor.isActive(mark) ? .accentColor : .secondary)
        .accessibilityLabel(label)
    }

    private func align(_ value: String, _ symbol: String) -> some View {
        Button { editor.view?.setTextAlign(value) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    private func toolButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityLabel(label)
    }

    private var listMenu: some View {
        Menu {
            Button("Bullet List", systemImage: "list.bullet") { editor.view?.wrapInList("bulletList") }
            Button("Ordered List", systemImage: "list.number") { editor.view?.wrapInList("orderedList") }
            Button("Task List", systemImage: "checklist") { editor.view?.wrapInList("taskList") }
        } label: {
            Image(systemName: "list.bullet")
                .frame(height: 30)
                .padding(.horizontal, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
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
                Button(hex) { editor.view?.toggleMark(.highlight(color: hex)) }
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

    func isActive(_ mark: Mark) -> Bool {
        view?.isActive(mark) ?? false
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

    fileprivate static let nesting = Document(.doc([
        .heading(level: 1, [.text("Block Nesting")]),
        .paragraph([.text("A blockquote is a container block: it holds other blocks and lays them out indented, with a rule down its left edge.")]),
        .blockquote([
            .paragraph([.text("This paragraph lives inside a blockquote.")]),
            .paragraph([.text("So does this one — two quoted paragraphs, one container.")]),
        ]),
        .paragraph([.text("And this paragraph is back at the top level, below the quote.")]),
    ]))

    fileprivate static let bulletList = Document(.doc([
        .heading(level: 1, [.text("Bullet List")]),
        .paragraph([.text("A bullet list is two levels of container — a bulletList of listItems, each holding a paragraph:")]),
        .bulletList([
            .listItem([.paragraph([.text("First item in the list.")])]),
            .listItem([.paragraph([.text("Second item, a little longer so it shows the marker stays put.")])]),
            .listItem([.paragraph([.text("Third and final item.")])]),
        ]),
        .paragraph([.text("And a plain paragraph back at the top level below the list.")]),
    ]))

    fileprivate static let orderedList = Document(.doc([
        .heading(level: 1, [.text("Ordered List")]),
        .paragraph([.text("An ordered list draws an ordinal per item, derived at draw time from the item's index among its siblings — nothing is stored in the model:")]),
        .orderedList([
            .listItem([.paragraph([.text("First step.")])]),
            .listItem([
                .paragraph([.text("Second step, with a nested ordered list:")]),
                .orderedList([
                    .listItem([.paragraph([.text("A nested item, numbered from one again.")])]),
                    .listItem([.paragraph([.text("Another nested item.")])]),
                ]),
            ]),
            .listItem([.paragraph([.text("Third step, back at the outer level.")])]),
        ]),
        .paragraph([.text("Press Tab at an item's start to sink it; Shift-Tab lifts it back out.")]),
    ]))

    fileprivate static let taskList = Document(.doc([
        .heading(level: 1, [.text("Task List")]),
        .paragraph([.text("A task list holds checkable items. Tap a checkbox to toggle its checked state:")]),
        .taskList([
            .taskItem(checked: true, [.paragraph([.text("A finished task — checked.")])]),
            .taskItem(checked: false, [.paragraph([.text("A task still to do.")])]),
            .taskItem(checked: false, [.paragraph([.text("Another open task, a little longer so the checkbox stays aligned to the first line.")])]),
        ]),
        .paragraph([.text("The checked attr survives split, join, sink and lift just like any list item.")]),
    ]))

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
