import ProseEditor
import ProseModel
import SwiftUI
import UIKit
import WebKit

@main
struct ProseExampleApp: App {
    var body: some Scene {
        WindowGroup {
            // -paragraphs N skips the demo list and shows a bare editor on a
            // large synthetic document, for exercising editing performance at
            // document scale (used by the ProseExampleUITests live-keyboard
            // and fling-scrolling tests, which expect the editor at root).
            if CommandLine.arguments.contains("-benchmark-toolbar") {
                // In-process benchmark of the formatting-toolbar rebuild cost
                // per editor-state change. Runs the real toolbar through
                // synchronous render passes so the measurement isn't swamped by
                // XCUITest's ~0.8s/keystroke event-synthesis overhead.
                ToolbarRebuildBenchmark()
            } else if let count = Self.syntheticUITextViewParagraphCount {
                BaselineTextEditorView(text: Document.syntheticPlainText(paragraphs: count))
                    .ignoresSafeArea(.keyboard)
            } else if let count = Self.syntheticParagraphCount {
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
                    } else if demo.id == "parity" {
                        ParityScreen(demo: demo)
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

    private static let syntheticUITextViewParagraphCount: Int? = {
        guard let index = CommandLine.arguments.firstIndex(of: "-uitextview-paragraphs"),
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
            id: "parity",
            title: "Tiptap Parity",
            subtitle: "Side-by-side with a real Tiptap editor; send documents either way to check round-trip fidelity",
            icon: "rectangle.split.2x1",
            makeDocument: { .parityShowcase }
        ),
        Demo(
            id: "uitextview",
            title: "UITextView Comparison",
            subtitle: "Side-by-side with a native UITextView on the same plain text, to spot behavioral differences",
            icon: "uiwindow.split.2x1",
            makeDocument: { .uitextviewComparison }
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
                } else if demo.id == "parity" {
                    ParityScreen(demo: demo)
                } else if demo.id == "uitextview" {
                    UITextViewComparisonScreen(demo: demo)
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
    private let swatches = [
        (name: "Yellow", hex: "#ffd54f"),
        (name: "Red", hex: "#ff8a80"),
        (name: "Blue", hex: "#80d8ff"),
        (name: "Green", hex: "#ccff90"),
        (name: "Purple", hex: "#ea80fc"),
    ]

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
                .disabled(!editor.canSetLink)
                .tint(editor.canSetLink ? .secondary : .gray)

                Divider().frame(height: 24)

                listMenu
                toolButton("increase.indent", "Indent", isEnabled: editor.canSinkListItem) { editor.view?.sinkListItem() }
                toolButton("decrease.indent", "Outdent", isEnabled: editor.canLiftListItem) { editor.view?.liftListItem() }
                toolButton("checklist.checked", "Toggle task", isEnabled: editor.canToggleTaskItemChecked) {
                    editor.view?.toggleTaskItemChecked()
                }

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
        // The toolbar observes `editor`, so a bumped `revision` already re-runs
        // this body and re-reads the active-state tints. An `.id(revision)` here
        // would also work, but it throws away the whole view tree (Menus and
        // all) and rebuilds it from scratch on every keystroke and caret move —
        // ~12× costlier per rebuild (see ToolbarRebuildBenchmark), the
        // main-thread hostage that made typing choppy on the simulator.
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

    private func toolButton(_ symbol: String, _ label: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.bordered)
            .tint(isEnabled ? .secondary : .gray)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
    }

    private var listMenu: some View {
        Menu {
            Button("Bullet List", systemImage: "list.bullet") { editor.view?.wrapInList("bulletList") }
            Button("Ordered List", systemImage: "list.number") { editor.view?.wrapInList("orderedList") }
            Button("Task List", systemImage: "checklist") { editor.view?.wrapInList("taskList") }
        } label: {
            menuIcon(listSymbol, isActive: editor.activeListType != nil)
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
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var highlightMenu: some View {
        Menu {
            Button("Remove Highlight", systemImage: "xmark.circle") {
                editor.view?.removeMark(type: "highlight")
            }
            .disabled(!editor.hasHighlight)
            Divider()
            ForEach(swatches, id: \.hex) { swatch in
                Button {
                    editor.view?.toggleMark(.highlight(color: swatch.hex))
                } label: {
                    Label {
                        Text(swatch.name)
                    } icon: {
                        Circle()
                            .fill(color(for: swatch.hex))
                    }
                }
            }
        } label: {
            menuIcon("highlighter", isActive: editor.hasHighlight)
        }
    }

    private var blockLabel: String {
        if let level = editor.headingLevel { return "H\(level)" }
        return "Paragraph"
    }

    private var listSymbol: String {
        switch editor.activeListType {
        case "orderedList": return "list.number"
        case "taskList": return "checklist"
        default: return "list.bullet"
        }
    }

    private func menuIcon(_ symbol: String, isActive: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .frame(height: 30)
        .padding(.horizontal, 8)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }

    private func color(for hex: String) -> Color {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt32(value, radix: 16) else { return .secondary }
        return Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
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
    private struct ToolbarState: Equatable {
        var activeMarks: Set<Mark> = []
        var headingLevel: Int?
        var activeListType: String?
        var canSinkListItem = false
        var canLiftListItem = false
        var canToggleTaskItemChecked = false
        var canSetLink = false
        var hasHighlight = false
    }

    private static let trackedMarks: [Mark] = [
        .bold,
        .italic,
        .underline,
        .strike,
        .code,
        .superscript,
        .subscript,
    ]

    weak var view: ProseView?
    @Published private var toolbarState = ToolbarState()
    @Published private(set) var revision = 0

    func bind(_ view: ProseView) {
        self.view = view
        updateToolbarState(from: view)
        view.onStateChange = { [weak self, weak view] in
            guard let self, let view else { return }
            self.updateToolbarState(from: view)
        }
    }

    /// Drives the same `revision` bump a keystroke / caret move does, for the
    /// in-process toolbar-rebuild benchmark.
    func bumpRevisionForBenchmark() { revision &+= 1 }

    private func updateToolbarState(from view: ProseView) {
        let next = ToolbarState(
            activeMarks: Set(Self.trackedMarks.filter { view.isActive($0) }),
            headingLevel: view.activeHeadingLevel,
            activeListType: view.activeListType,
            canSinkListItem: view.canSinkListItem,
            canLiftListItem: view.canLiftListItem,
            canToggleTaskItemChecked: view.canToggleTaskItemChecked,
            canSetLink: view.canSetLink,
            hasHighlight: view.hasHighlight
        )
        guard next != toolbarState else { return }
        toolbarState = next
    }

    func isActive(_ mark: Mark) -> Bool {
        toolbarState.activeMarks.contains(mark)
    }

    var headingLevel: Int? { toolbarState.headingLevel }
    var activeListType: String? { toolbarState.activeListType }
    var canSinkListItem: Bool { toolbarState.canSinkListItem }
    var canLiftListItem: Bool { toolbarState.canLiftListItem }
    var canToggleTaskItemChecked: Bool { toolbarState.canToggleTaskItemChecked }
    var canSetLink: Bool { toolbarState.canSetLink }
    var hasHighlight: Bool { toolbarState.hasHighlight }
}

/// Measures how long the formatting toolbar takes to react to one editor-state
/// change (the bump a keystroke or caret move triggers). Hosts the real
/// `SimpleEditorToolbar` and drives it through synchronous render passes with
/// `CATransaction.flush()`, so it measures SwiftUI's actual rebuild work rather
/// than XCUITest's event-synthesis overhead. Guards the `.id(revision)` trap,
/// which made every bump tear down and rebuild the whole toolbar tree.
private struct ToolbarRebuildBenchmark: View {
    @State private var result = "running…"

    var body: some View {
        VStack(spacing: 12) {
            Text("Toolbar Rebuild Benchmark").font(.headline)
            Text(result)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("toolbar-rebuild-result")
        }
        .padding()
        .task { result = await Self.run() }
    }

    @MainActor
    static func run(iterations: Int = 400) async -> String {
        let proxy = EditorProxy()
        let editor = ProseView(document: .simpleEditor)
        proxy.bind(editor)

        let host = UIHostingController(rootView: SimpleEditorToolbar(editor: proxy))
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 52)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window?.addSubview(host.view)
        host.view.layoutIfNeeded()
        CATransaction.flush()

        func driveOneRebuild() {
            proxy.bumpRevisionForBenchmark()
            CATransaction.flush()
        }

        for _ in 0..<40 { driveOneRebuild() } // warm up CoreText / SwiftUI caches

        let start = CACurrentMediaTime()
        for _ in 0..<iterations { driveOneRebuild() }
        let elapsed = CACurrentMediaTime() - start

        host.view.removeFromSuperview()

        let perRebuildMs = elapsed / Double(iterations) * 1000
        let line = String(format: "%.4f ms/rebuild over %d", perRebuildMs, iterations)
        print("[toolbar-benchmark] \(line)")
        return line
    }
}

// MARK: - Tiptap Parity (split-screen comparison)

/// Splits the screen between a real Tiptap editor (left) and our editor (right)
/// so the two can be compared on the same document. The action bar bridges a
/// ProseMirror-JSON document either way, or resets/clears both at once — the
/// truth test for whether our editor reads and writes the model the same way
/// the reference implementation does.
private struct ParityScreen: View {
    let demo: Demo
    @StateObject private var controller = ParityController()
    @StateObject private var editor = EditorProxy()

    var body: some View {
        VStack(spacing: 0) {
            ParityActionBar(controller: controller)
            Divider()
            HStack(spacing: 0) {
                pane("Tiptap (reference)") {
                    TiptapWebView(controller: controller)
                }
                Divider()
                pane("Prose (ours)") {
                    VStack(spacing: 0) {
                        ParityProseView(controller: controller, editor: editor)
                        Divider()
                        SimpleEditorToolbar(editor: editor)
                    }
                }
            }
        }
        .navigationTitle(demo.title)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.quaternary)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ParityActionBar: View {
    @ObservedObject var controller: ParityController

    var body: some View {
        HStack(spacing: 8) {
            Button { controller.sendLeftToRight() } label: {
                Label("Send →", systemImage: "arrow.right")
            }
            Button { controller.sendRightToLeft() } label: {
                Label("← Send", systemImage: "arrow.left")
            }
            Spacer()
            Button { controller.reset() } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) { controller.clear() } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Owns the live references to both editors and bridges ProseMirror-JSON between
/// them. The reference editor lives in JavaScript, so reads are async (one
/// `evaluateJavaScript` round trip); writes inject the JSON object straight into
/// a call (JSON is valid JS, so no escaping is needed).
@MainActor private final class ParityController: ObservableObject {
    weak var webView: WKWebView?
    weak var proseView: ProseView?
    private var tiptapReady = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Called once the web editor reports it is live; seeds it with the same
    /// showcase document our editor opens on.
    func tiptapDidBecomeReady() {
        tiptapReady = true
        pushToTiptap(.parityShowcase)
    }

    func sendLeftToRight() {
        readTiptap { [weak self] document in
            guard let self, let document else { return }
            self.proseView?.document = document
        }
    }

    func sendRightToLeft() {
        guard let document = proseView?.document else { return }
        pushToTiptap(document)
    }

    func reset() {
        proseView?.document = .parityShowcase
        pushToTiptap(.parityShowcase)
    }

    func clear() {
        let empty = Document(.doc([.paragraph([])]))
        proseView?.document = empty
        pushToTiptap(empty)
    }

    private func pushToTiptap(_ document: Document) {
        guard let webView, tiptapReady,
              let data = try? encoder.encode(document),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.setDocObject(\(json)); true;")
    }

    private func readTiptap(_ completion: @escaping (Document?) -> Void) {
        guard let webView, tiptapReady else { completion(nil); return }
        webView.evaluateJavaScript("window.getDoc()") { result, _ in
            MainActor.assumeIsolated {
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let document = try? self.decoder.decode(Document.self, from: data) else {
                    completion(nil)
                    return
                }
                completion(document)
            }
        }
    }
}

/// A real Tiptap / ProseMirror editor in a `WKWebView`, configured to mirror our
/// Schema. The HTML loads Tiptap from a CDN, so this pane needs network access.
private struct TiptapWebView: UIViewRepresentable {
    let controller: ParityController

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "ready")
        configuration.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        controller.webView = webView
        context.coordinator.controller = controller

        if let url = Bundle.main.url(forResource: "TiptapEditor", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            // Load via a synthetic https base URL (never actually fetched) so the
            // document has a normal origin — file:// origins block the ES-module
            // imports the editor depends on.
            webView.loadHTMLString(html, baseURL: URL(string: "https://prose.local/"))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var controller: ParityController?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "ready" else { return }
            controller?.tiptapDidBecomeReady()
        }
    }
}

/// Our editor for the right pane: bound to both the shared `EditorProxy` (so the
/// formatting toolbar tracks it) and the `ParityController` (so the action bar
/// can read and replace its document). It does not auto-focus, so the keyboard
/// stays down until tapped and both panes remain visible side by side.
private struct ParityProseView: UIViewRepresentable {
    let controller: ParityController
    let editor: EditorProxy

    func makeUIView(context: Context) -> ProseView {
        let view = ProseView(document: .parityShowcase)
        editor.bind(view)
        controller.proseView = view
        return view
    }

    func updateUIView(_ uiView: ProseView, context: Context) {}
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

private struct BaselineTextEditorView: UIViewRepresentable {
    let text: String
    /// The performance benchmark needs the caret up immediately; the comparison
    /// demo wants both panes idle until tapped, so this is opt-out.
    var focusesOnAppear = true

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .systemFont(ofSize: 17)
        view.text = text
        if focusesOnAppear {
            DispatchQueue.main.async {
                _ = view.becomeFirstResponder()
            }
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
}

// MARK: - UITextView Comparison (behavioral side-by-side)

/// Splits the screen between a native `UITextView` (left) and a bare `ProseView`
/// (right) seeded with the *same* plain text. Unlike Tiptap Parity there is no
/// bridge between the panes and no formatting chrome — the point is to poke each
/// editing surface and discover where our behavior diverges from UIKit's
/// (caret movement, selection handles, the edit menu, autocorrect, autoscroll).
private struct UITextViewComparisonScreen: View {
    let demo: Demo

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pane("UITextView (native)") {
                    BaselineTextEditorView(
                        text: Document.uitextviewComparisonText,
                        focusesOnAppear: false
                    )
                }
                Divider()
                pane("Prose (ours)") {
                    BareProseView(document: demo.makeDocument())
                }
            }
        }
        .navigationTitle(demo.title)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.quaternary)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A `ProseView` with no formatting toolbar and no auto-focus — the plainest
/// editing surface we offer, so it compares apples-to-apples with a bare
/// `UITextView`.
private struct BareProseView: UIViewRepresentable {
    let document: Document

    func makeUIView(context: Context) -> ProseView {
        ProseView(document: document)
    }

    func updateUIView(_ uiView: ProseView, context: Context) {}
}

// MARK: - Demo documents

extension Document {
    static func synthetic(paragraphs count: Int) -> Document {
        Document(.doc((1...count).map { n in
            .paragraph([.text(Self.syntheticParagraphText(n))])
        }))
    }

    static func syntheticPlainText(paragraphs count: Int) -> String {
        (1...count).map(Self.syntheticParagraphText).joined(separator: "\n")
    }

    private static func syntheticParagraphText(_ n: Int) -> String {
        let sentence = "The quick brown fox jumps over the lazy dog near the quiet river bank. "
        let body = String(repeating: sentence, count: 3)
        return "Paragraph \(n). " + body
    }

    /// The single source of truth for the UITextView Comparison demo: a few long,
    /// wrapping paragraphs that exercise caret movement, multi-line selection, the
    /// edit menu, autocorrect, and drag-to-edge autoscroll. Both panes are built
    /// from this same array so their starting content cannot drift apart.
    private static let uitextviewComparisonParagraphs = [
        "Type into either side and watch how they differ. Move the caret word by word, double-tap to select, drag the selection handles, and bring up the edit menu — the native UITextView on the left is the behavior we measure ourselves against.",
        "This paragraph is deliberately long so it wraps across several lines on a phone. Wrapping is where caret arithmetic, line-fragment hit testing, and selection geometry tend to disagree, so compare where the caret lands when you tap mid-word or at the very end of a wrapped line.",
        "Try autocorrect and predictive text, then undo with a three-finger swipe or a shake. Try selecting across this paragraph boundary into the next one, and drag toward the top or bottom edge to trigger autoscroll while a selection is active.",
        "Finally, scroll both panes with a fling and see how momentum, rubber-banding, and the resting position compare. Small divergences here are exactly the kind of thing this side-by-side is meant to surface.",
    ]

    /// The comparison fixture as a ProseView Document (plain paragraphs, no marks).
    fileprivate static let uitextviewComparison = Document(.doc(
        uitextviewComparisonParagraphs.map { .paragraph([.text($0)]) }
    ))

    /// The same fixture as the plain string a UITextView understands.
    fileprivate static let uitextviewComparisonText =
        uitextviewComparisonParagraphs.joined(separator: "\n\n")

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

    /// A made-up document about a text editor that exercises every block and
    /// inline style our Schema supports, so the parity screen can round-trip the
    /// full feature set through the reference editor.
    fileprivate static let parityShowcase = Document(.doc([
        .heading(level: 1, [.text("The Quill Field Guide")]),
        .paragraph([
            .text("A short manual on the craft of editing text. It mixes "),
            .text("bold", marks: [.bold]),
            .text(", "),
            .text("italic", marks: [.italic]),
            .text(", "),
            .text("underline", marks: [Mark(type: "underline")]),
            .text(", "),
            .text("strikethrough", marks: [Mark(type: "strike")]),
            .text(", and "),
            .text("inline code", marks: [.code]),
            .text(" so every mark has a turn."),
        ]),
        .paragraph([
            .text("Marks also "),
            .text("compose", marks: [.bold, .italic]),
            .text(": this run is bold and italic at once. Chemists write H"),
            .text("2", marks: [Mark(type: "subscript")]),
            .text("O, while physicists prefer E = mc"),
            .text("2", marks: [Mark(type: "superscript")]),
            .text("."),
        ]),
        .heading(level: 2, [.text("Highlights and links")]),
        .paragraph([
            .text("Reviewers reach for a "),
            .text("yellow highlighter", marks: [Mark(type: "highlight", attrs: ["color": .string("#ffd54f")])]),
            .text(", and sometimes "),
            .text("a blue one", marks: [Mark(type: "highlight", attrs: ["color": .string("#80d8ff")])]),
            .text(" for a second pass. References point outward, like "),
            .text("example.com", marks: [Mark(type: "link", attrs: ["href": .string("https://example.com")])]),
            .text("."),
        ]),
        Node(
            type: "paragraph",
            attrs: ["textAlign": .string("center")],
            content: [.text("A centered caption sits beneath the figure.")]
        ),
        Node(
            type: "paragraph",
            attrs: ["textAlign": .string("right")],
            content: [.text("— attributed, flush right")]
        ),
        Node(
            type: "paragraph",
            attrs: ["textAlign": .string("justify")],
            content: [.text("Justified body text spreads each line to both margins, which is how dense columns keep a tidy right edge even when the words inside them vary in length from one line to the next.")]
        ),
        .heading(level: 3, [.text("A word of caution")]),
        .blockquote([
            .paragraph([.text("Structure first, styling second. A document is a tree of blocks; the look is only a projection of it.")]),
            .paragraph([.text("— every editor's first lesson")]),
        ]),
        .heading(level: 4, [.text("Things to try")]),
        .bulletList([
            .listItem([.paragraph([.text("Select a word and toggle a mark.")])]),
            .listItem([.paragraph([.text("Turn a paragraph into a heading.")])]),
            .listItem([.paragraph([.text("Send this document the other way and compare.")])]),
        ]),
        .heading(level: 5, [.text("A numbered recipe")]),
        .orderedList([
            .listItem([.paragraph([.text("Place the caret where you want a split.")])]),
            .listItem([
                .paragraph([.text("Press Return; the block divides. Nested steps follow:")]),
                .orderedList([
                    .listItem([.paragraph([.text("The inner list numbers from one again.")])]),
                    .listItem([.paragraph([.text("Shift-Tab lifts an item back out.")])]),
                ]),
            ]),
            .listItem([.paragraph([.text("Backspace at the start joins it back.")])]),
        ]),
        .heading(level: 6, [.text("A checklist before you ship")]),
        .taskList([
            .taskItem(checked: true, [.paragraph([.text("Round-trip every block type.")])]),
            .taskItem(checked: true, [.paragraph([.text("Round-trip every inline mark.")])]),
            .taskItem(checked: false, [.paragraph([.text("Confirm alignment survives the trip.")])]),
            .taskItem(checked: false, [.paragraph([.text("Confirm nested lists survive the trip.")])]),
        ]),
        .paragraph([.text("That is the whole vocabulary — headings one through six, paragraphs, alignment, every mark, quotes, all three list kinds, and nesting.")]),
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
