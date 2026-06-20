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
    let canvasView = MacCanvasView()
    let selectionLayer = MacSelectionLayerView()
    private let editorContentView = MacEditorContentView()

    public init(document: Document, schema: Schema = .slice1) {
        self.core = EditorCore(document: document, schema: schema)
        super.init(frame: .zero)
        drawsBackground = true
        backgroundColor = .canvasBackground
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        editorContentView.onMouseDown = { [weak self] point in
            self?.placeCaret(atContentPoint: point)
        }
        editorContentView.addSubview(canvasView)
        editorContentView.addSubview(selectionLayer)
        documentView = editorContentView
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

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        selectionLayer.setEditorIsFirstResponder(true)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        selectionLayer.setEditorIsFirstResponder(false)
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        placeCaret(atContentPoint: convert(event.locationInWindow, from: nil))
    }

    func placeCaret(atContentPoint point: CGPoint) {
        if let window {
            window.makeFirstResponder(self)
        } else {
            _ = becomeFirstResponder()
        }
        let position = core.closestPosition(to: point)
        core.setSelection(TextSelection(anchor: position, head: position))
        updateSelectionLayer()
    }

    private func relayout() {
        let width = max(1, contentView.bounds.width)
        core.relayout(width: width)
        setAccessibilityValue(core.document.plainText)
        canvasView.layoutBox = core.layoutBox
        let contentSize = core.layoutBox?.frame.size ?? .zero
        let frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: max(contentView.bounds.height, contentSize.height)
        )
        editorContentView.frame = frame
        canvasView.frame = editorContentView.bounds
        selectionLayer.frame = editorContentView.bounds
        canvasView.needsDisplay = true
        updateSelectionLayer()
    }

    private func updateSelectionLayer() {
        selectionLayer.selection = core.selection
        selectionLayer.caretRect = core.caretRect(for: core.selection.head)
    }
}

@MainActor final class MacEditorContentView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
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
