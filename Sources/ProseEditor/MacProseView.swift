#if canImport(AppKit)
import AppKit
import ProseModel
import SwiftUI

@MainActor public final class ProseView: NSScrollView {
    public var document: Document {
        get { core.document }
        set {
            core.document = newValue
            needsLayout = true
        }
    }

    public let core: EditorCore
    private let canvas = MacCanvasView()

    public init(document: Document, schema: Schema = .slice1) {
        self.core = EditorCore(document: document, schema: schema)
        super.init(frame: .zero)
        drawsBackground = true
        backgroundColor = .canvasBackground
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        documentView = canvas
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Prose editor")
        setAccessibilityValue(document.plainText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func layout() {
        super.layout()
        relayout()
    }

    private func relayout() {
        let width = max(1, contentView.bounds.width)
        core.relayout(width: width)
        setAccessibilityValue(core.document.plainText)
        canvas.layoutBox = core.layoutBox
        let contentSize = core.layoutBox?.frame.size ?? .zero
        canvas.frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: max(contentView.bounds.height, contentSize.height)
        )
        canvas.needsDisplay = true
    }
}

public struct MacProseEditorView: NSViewRepresentable {
    public var document: Document

    public init(document: Document) {
        self.document = document
    }

    public func makeNSView(context: Context) -> ProseView {
        ProseView(document: document)
    }

    public func updateNSView(_ nsView: ProseView, context: Context) {
        nsView.document = document
    }
}
#endif
