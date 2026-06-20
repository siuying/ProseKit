#if canImport(AppKit)
import AppKit
import ProseModel
import SwiftUI

@MainActor public final class ProseView: NSScrollView, NSUserInterfaceValidations, NSMenuItemValidation {
    public var document: Document {
        get { core.document }
        set {
            core.document = newValue
            needsLayout = true
        }
    }

    public let core: EditorCore
    public var pasteboard: Pasteboard = NSPasteboard.general
    let canvasView = MacCanvasView()
    let selectionLayer = MacSelectionLayerView()
    private let editorContentView = MacEditorContentView()
    private var markedTextPositionRange: Range<Position>?
    private var selectionAnchor: Position?

    public init(document: Document, schema: Schema = .slice1) {
        self.core = EditorCore(document: document, schema: schema)
        super.init(frame: .zero)
        drawsBackground = true
        backgroundColor = .canvasBackground
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        editorContentView.onMouseDown = { [weak self] event in
            self?.handleMouseDown(event)
        }
        editorContentView.onMouseDragged = { [weak self] point in
            self?.extendSelection(toContentPoint: point)
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
        handleMouseDown(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        extendSelection(toContentPoint: editorContentView.convert(event.locationInWindow, from: nil))
    }

    public override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    public override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            deleteBackwardFromInput()
        case #selector(NSResponder.insertNewline(_:)):
            runInputCommand(Commands.splitBlock())
        case #selector(NSResponder.insertTab(_:)):
            runKeyBinding(key: .tab, modifiers: [])
        case #selector(NSResponder.insertBacktab(_:)):
            runKeyBinding(key: .tab, modifiers: .shift)
        case #selector(NSResponder.moveLeft(_:)):
            moveCaret(to: core.position(before: core.selection.head), extending: false)
        case #selector(NSResponder.moveRight(_:)):
            moveCaret(to: core.position(after: core.selection.head), extending: false)
        case #selector(NSResponder.moveUp(_:)):
            moveCaret(to: core.position(above: core.selection.head), extending: false)
        case #selector(NSResponder.moveDown(_:)):
            moveCaret(to: core.position(below: core.selection.head), extending: false)
        case #selector(NSResponder.moveLeftAndModifySelection(_:)):
            moveCaret(to: core.position(before: core.selection.head), extending: true)
        case #selector(NSResponder.moveRightAndModifySelection(_:)):
            moveCaret(to: core.position(after: core.selection.head), extending: true)
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            moveCaret(to: core.position(above: core.selection.head), extending: true)
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            moveCaret(to: core.position(below: core.selection.head), extending: true)
        case #selector(NSResponder.moveWordLeft(_:)):
            moveCaret(to: wordBoundary(from: core.selection.head, direction: .backward), extending: false)
        case #selector(NSResponder.moveWordRight(_:)):
            moveCaret(to: wordBoundary(from: core.selection.head, direction: .forward), extending: false)
        case #selector(NSResponder.moveWordLeftAndModifySelection(_:)):
            moveCaret(to: wordBoundary(from: core.selection.head, direction: .backward), extending: true)
        case #selector(NSResponder.moveWordRightAndModifySelection(_:)):
            moveCaret(to: wordBoundary(from: core.selection.head, direction: .forward), extending: true)
        case #selector(NSResponder.moveToBeginningOfLine(_:)),
             #selector(NSResponder.moveToBeginningOfParagraph(_:)):
            moveCaret(to: paragraphBoundary(from: core.selection.head, edge: .start), extending: false)
        case #selector(NSResponder.moveToEndOfLine(_:)),
             #selector(NSResponder.moveToEndOfParagraph(_:)):
            moveCaret(to: paragraphBoundary(from: core.selection.head, edge: .end), extending: false)
        case #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)),
             #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)):
            moveCaret(to: paragraphBoundary(from: core.selection.head, edge: .start), extending: true)
        case #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)),
             #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)):
            moveCaret(to: paragraphBoundary(from: core.selection.head, edge: .end), extending: true)
        case #selector(NSResponder.deleteWordBackward(_:)):
            deleteWord(direction: .backward)
        case #selector(NSResponder.deleteWordForward(_:)):
            deleteWord(direction: .forward)
        default:
            super.doCommand(by: selector)
        }
    }

    @objc public func copy(_ sender: Any?) {
        guard !core.selection.isCollapsed else { return }
        pasteboard.string = selectedPlainText()
    }

    @objc public func cut(_ sender: Any?) {
        guard !core.selection.isCollapsed else { return }
        pasteboard.string = selectedPlainText()
        do {
            try core.insertText("")
        } catch is StepError {
            // Unsupported edit: leave the document untouched.
        } catch {
            assertionFailure("cut failed: \(error)")
        }
        relayout()
    }

    @objc public func paste(_ sender: Any?) {
        guard let text = pasteboard.string else { return }
        insertTextFromInput(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @objc public func undo(_ sender: Any?) {
        guard core.undo() else { return }
        relayout()
    }

    @objc public func redo(_ sender: Any?) {
        guard core.redo() else { return }
        relayout()
    }

    public override func selectAll(_ sender: Any?) {
        core.setSelection(ProseModel.TextSelection(anchor: core.document.startTextPosition, head: core.document.endTextPosition))
        updateSelectionLayer()
    }

    @objc public func toggleBoldface(_ sender: Any?) {
        runKeyBinding(key: .character("b"), modifiers: .command)
    }

    @objc public func toggleItalics(_ sender: Any?) {
        runKeyBinding(key: .character("i"), modifiers: .command)
    }

    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        canPerformEditAction(for: item.action)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleBoldface(_:)):
            menuItem.state = core.state.isActive(.bold) ? .on : .off
            return true
        case #selector(toggleItalics(_:)):
            menuItem.state = core.state.isActive(.italic) ? .on : .off
            return true
        case #selector(undo(_:)):
            return core.canUndo
        case #selector(redo(_:)):
            return core.canRedo
        default:
            break
        }
        return canPerformEditAction(for: menuItem.action)
    }

    func placeCaret(atContentPoint point: CGPoint) {
        if let window {
            window.makeFirstResponder(self)
        } else {
            _ = becomeFirstResponder()
        }
        selectionAnchor = nil
        let position = core.closestPosition(to: point)
        core.setSelection(ProseModel.TextSelection(anchor: position, head: position))
        updateSelectionLayer()
    }

    func beginSelection(atContentPoint point: CGPoint) {
        if let window {
            window.makeFirstResponder(self)
        } else {
            _ = becomeFirstResponder()
        }
        let position = core.closestPosition(to: point)
        selectionAnchor = position
        core.setSelection(ProseModel.TextSelection(anchor: position, head: position))
        updateSelectionLayer()
    }

    func extendSelection(toContentPoint point: CGPoint) {
        let head = core.closestPosition(to: point)
        let anchor = selectionAnchor ?? core.selection.anchor
        selectionAnchor = anchor
        core.setSelection(ProseModel.TextSelection(anchor: anchor, head: head))
        updateSelectionLayer()
    }

    func selectWord(atContentPoint point: CGPoint) {
        let nearestPosition = core.closestPosition(to: point)
        // Scope the scan to the block under the caret: plainText joins blocks
        // with no separator, so scanning the whole document would merge words
        // across paragraph boundaries (and materialize the entire document).
        guard let info = core.document.blockInfo(containing: nearestPosition),
              let count = core.document.textCount(ofBlockAt: info.index), count > 0 else {
            placeCaret(atContentPoint: point)
            return
        }
        let blockText = Array(info.node.plainText)
        let blockTextStart = info.start + 1
        var index = max(0, min(count - 1, nearestPosition - blockTextStart))
        if blockText[index].isWhitespace, index > 0 {
            index -= 1
        }
        var lower = index
        var upper = index + 1
        while lower > 0, !blockText[lower - 1].isWhitespace {
            lower -= 1
        }
        while upper < blockText.count, !blockText[upper].isWhitespace {
            upper += 1
        }
        let anchor = blockTextStart + lower
        let head = blockTextStart + upper
        selectionAnchor = anchor
        core.setSelection(ProseModel.TextSelection(anchor: anchor, head: head))
        updateSelectionLayer()
    }

    func selectParagraph(atContentPoint point: CGPoint) {
        let position = core.closestPosition(to: point)
        guard let info = core.document.blockInfo(containing: position),
              let count = core.document.textCount(ofBlockAt: info.index) else {
            placeCaret(atContentPoint: point)
            return
        }
        let anchor = info.start + 1
        let head = anchor + count
        selectionAnchor = anchor
        core.setSelection(ProseModel.TextSelection(anchor: anchor, head: head))
        updateSelectionLayer()
    }

    private enum TextDirection {
        case backward
        case forward
    }

    private enum ParagraphEdge {
        case start
        case end
    }

    private func moveCaret(to position: Position, extending: Bool) {
        let clamped = core.clamp(position)
        let anchor = extending ? core.selection.anchor : clamped
        core.setSelection(ProseModel.TextSelection(anchor: anchor, head: clamped))
        selectionAnchor = extending ? anchor : nil
        updateSelectionLayer()
    }

    private func paragraphBoundary(from position: Position, edge: ParagraphEdge) -> Position {
        guard let info = core.document.blockInfo(containing: position),
              let count = core.document.textCount(ofBlockAt: info.index) else {
            return position
        }
        let start = info.start + 1
        return edge == .start ? start : start + count
    }

    private func wordBoundary(from position: Position, direction: TextDirection) -> Position {
        // Scan within the current block (plainText has no block separators, so a
        // whole-document scan would skip whole paragraphs as one "word"). When
        // the caret is already at the block's edge, step into the adjacent block
        // so word motion still crosses paragraph boundaries.
        guard let info = core.document.blockInfo(containing: position),
              let count = core.document.textCount(ofBlockAt: info.index) else {
            return position
        }
        let blockText = Array(info.node.plainText)
        let blockTextStart = info.start + 1
        var local = max(0, min(count, position - blockTextStart))
        let startLocal = local
        switch direction {
        case .forward:
            while local < blockText.count, blockText[local].isWhitespace { local += 1 }
            while local < blockText.count, !blockText[local].isWhitespace { local += 1 }
            if local == startLocal {
                guard info.index + 1 < core.document.blockCount,
                      let nextStart = core.document.position(ofTextInBlockAt: info.index + 1) else {
                    return position
                }
                return wordBoundary(from: nextStart, direction: .forward)
            }
        case .backward:
            while local > 0, blockText[local - 1].isWhitespace { local -= 1 }
            while local > 0, !blockText[local - 1].isWhitespace { local -= 1 }
            if local == startLocal {
                guard info.index > 0,
                      let previousStart = core.document.position(ofTextInBlockAt: info.index - 1),
                      let previousCount = core.document.textCount(ofBlockAt: info.index - 1) else {
                    return position
                }
                return wordBoundary(from: previousStart + previousCount, direction: .backward)
            }
        }
        return blockTextStart + local
    }

    private func deleteWord(direction: TextDirection) {
        let target = wordBoundary(from: core.selection.head, direction: direction)
        guard target != core.selection.head else { return }
        core.setSelection(ProseModel.TextSelection(anchor: core.selection.head, head: target))
        do {
            try core.insertText("")
        } catch is StepError {
            // Unsupported edit: leave the document untouched.
        } catch {
            assertionFailure("delete word failed: \(error)")
        }
        relayout()
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
        selectionLayer.selectionRects = core.selectionRects(for: core.selection)
        selectionLayer.setWindowIsKey(window?.isKeyWindow ?? true)
    }

    private func handleMouseDown(_ event: NSEvent) {
        let point = editorContentView.convert(event.locationInWindow, from: nil)
        if event.clickCount >= 3 {
            selectParagraph(atContentPoint: point)
        } else if event.clickCount == 2 {
            selectWord(atContentPoint: point)
        } else {
            beginSelection(atContentPoint: point)
        }
    }

    private func selectedPlainText() -> String {
        let lower = min(core.selection.anchor, core.selection.head)
        let upper = max(core.selection.anchor, core.selection.head)
        return core.document.plainText(from: lower, to: upper)
    }

    private func canPerformEditAction(for selector: Selector?) -> Bool {
        switch selector {
        case #selector(copy(_:)):
            return core.canPerformEditAction(.copy, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(cut(_:)):
            return core.canPerformEditAction(.cut, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(paste(_:)):
            return core.canPerformEditAction(.paste, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(selectAll(_:)):
            return core.canPerformEditAction(.selectAll, pasteboardHasStrings: pasteboard.hasStrings)
        default:
            return true
        }
    }

    private func insertTextFromInput(_ text: String, replacementRange: NSRange) {
        let hadMarkedText = hasMarkedText()
        selectReplacementRange(replacementRange)
        let segments = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                _ = core.run(Commands.splitBlock())
            }
            if !segment.isEmpty || segments.count == 1 {
                do {
                    try core.insertText(segment)
                } catch is StepError {
                    // Unsupported edit: leave the document untouched.
                } catch {
                    assertionFailure("insertText failed: \(error)")
                }
            }
        }
        if hadMarkedText || replacementRange.location != NSNotFound {
            clearMarkedText()
        }
        relayout()
    }

    private func deleteBackwardFromInput() {
        do {
            if try core.dispatch(Commands.joinBackward())
                || core.dispatch(Commands.liftOutOfContainer()) {
                relayout()
                return
            }
            try core.deleteBackward()
        } catch is StepError {
            // Unsupported edit: leave the document untouched.
        } catch {
            assertionFailure("deleteBackward failed: \(error)")
        }
        relayout()
    }

    private func runInputCommand(_ command: Command) {
        _ = core.run(command)
        relayout()
    }

    private func runKeyBinding(key: EditorKeyBinding.Key, modifiers: EditorKeyModifiers) {
        guard let binding = core.keyBinding(for: key, modifiers: modifiers) else { return }
        _ = core.runKeyBindingAction(binding.action)
        relayout()
    }

    private func selectReplacementRange(_ replacementRange: NSRange) {
        guard replacementRange.location != NSNotFound else { return }
        core.setSelection(textSelection(forCharacterRange: replacementRange))
    }

    private func clearMarkedText() {
        markedTextPositionRange = nil
    }

    private func deleteMarkedSelection() {
        do {
            try core.insertText("")
        } catch is StepError {
            // Unsupported edit: leave the document untouched.
        } catch {
            assertionFailure("clearing marked text failed: \(error)")
        }
        relayout()
    }
}

extension ProseView: @preconcurrency NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        insertTextFromInput(Self.inputString(from: string), replacementRange: replacementRange)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = Self.inputString(from: string)
        guard !text.isEmpty else {
            // Clearing the composition must remove the provisional text already
            // inserted, not just drop the range we were tracking.
            if let markedTextPositionRange {
                core.setSelection(ProseModel.TextSelection(anchor: markedTextPositionRange.lowerBound, head: markedTextPositionRange.upperBound))
                deleteMarkedSelection()
            }
            unmarkText()
            return
        }
        if let markedTextPositionRange, replacementRange.location == NSNotFound {
            core.setSelection(ProseModel.TextSelection(anchor: markedTextPositionRange.lowerBound, head: markedTextPositionRange.upperBound))
        } else {
            selectReplacementRange(replacementRange)
        }
        let lower = min(core.selection.anchor, core.selection.head)
        insertTextFromInput(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        markedTextPositionRange = lower..<(lower + text.count)
        let selectedStart = core.clamp(lower + selectedRange.location)
        let selectedEnd = core.clamp(selectedStart + selectedRange.length)
        core.setSelection(ProseModel.TextSelection(anchor: selectedStart, head: selectedEnd))
        updateSelectionLayer()
    }

    public func unmarkText() {
        clearMarkedText()
    }

    public func selectedRange() -> NSRange {
        characterRange(for: core.selection)
    }

    public func markedRange() -> NSRange {
        guard let markedTextPositionRange else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let start = characterOffset(for: markedTextPositionRange.lowerBound)
        let end = characterOffset(for: markedTextPositionRange.upperBound)
        return NSRange(location: start, length: max(0, end - start))
    }

    public func hasMarkedText() -> Bool {
        markedTextPositionRange != nil
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound else { return nil }
        let text = core.document.plainText
        let lower = max(0, min(range.location, text.count))
        let upper = max(lower, min(range.location + range.length, text.count))
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        actualRange?.pointee = NSRange(location: lower, length: upper - lower)
        return NSAttributedString(string: String(text[start..<end]))
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        let position = position(forCharacterOffset: range.location == NSNotFound ? core.document.totalTextCount : range.location)
        let rect = core.caretRect(for: position)
        let windowRect = editorContentView.convert(rect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    public func characterIndex(for point: NSPoint) -> Int {
        let windowPoint = window?.convertPoint(fromScreen: point) ?? point
        let contentPoint = editorContentView.convert(windowPoint, from: nil)
        return characterOffset(for: core.closestPosition(to: contentPoint))
    }

    private static func inputString(from value: Any) -> String {
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return String(describing: value)
    }

    fileprivate func textSelection(forCharacterRange range: NSRange) -> ProseModel.TextSelection {
        let anchor = position(forCharacterOffset: range.location)
        let head = position(forCharacterOffset: range.location + range.length)
        return ProseModel.TextSelection(anchor: anchor, head: head)
    }

    fileprivate func characterRange(for selection: ProseModel.TextSelection) -> NSRange {
        let anchor = characterOffset(for: selection.anchor)
        let head = characterOffset(for: selection.head)
        return NSRange(location: min(anchor, head), length: head >= anchor ? head - anchor : anchor - head)
    }

    fileprivate func characterOffset(for position: Position) -> Int {
        guard let info = core.document.blockInfo(containing: position),
              let blockTextStart = core.document.blockTextStart(at: position),
              let textCount = core.document.textCount(ofBlockAt: info.index),
              let charactersBefore = core.document.textCharacters(beforeBlockAt: info.index) else {
            return core.document.totalTextCount
        }
        let local = max(0, min(textCount, position - blockTextStart))
        return charactersBefore + local
    }

    fileprivate func position(forCharacterOffset offset: Int) -> Position {
        var remaining = max(0, offset)
        for blockIndex in 0..<core.document.blockCount {
            guard let count = core.document.textCount(ofBlockAt: blockIndex),
                  let start = core.document.position(ofTextInBlockAt: blockIndex) else { continue }
            if remaining <= count {
                return start + remaining
            }
            remaining -= count
        }
        return core.document.endTextPosition
    }
}

@MainActor final class MacEditorContentView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?

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
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
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

public enum MacProseFormatMenu {
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        for binding in EditorCore.sharedKeyBindings {
            guard let item = menuItem(for: binding) else { continue }
            menu.addItem(item)
        }
        return menu
    }

    private static func menuItem(for binding: EditorKeyBinding) -> NSMenuItem? {
        switch binding.action {
        case .toggleBold:
            return menuItem(title: "Bold", binding: binding, action: #selector(ProseView.toggleBoldface(_:)))
        case .toggleItalic:
            return menuItem(title: "Italic", binding: binding, action: #selector(ProseView.toggleItalics(_:)))
        case .sinkListItem, .liftListItem:
            return nil
        }
    }

    private static func menuItem(title: String, binding: EditorKeyBinding, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: binding.key.keyEquivalent)
        item.keyEquivalentModifierMask = NSEvent.ModifierFlags(binding.modifiers)
        return item
    }
}

/// The standard Edit menu (Undo/Redo/Cut/Copy/Paste/Select All) wired to
/// `ProseView`'s responder actions, so host apps install one menu instead of
/// re-deriving these shortcuts.
public enum MacProseEditMenu {
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", #selector(ProseView.undo(_:)), "z", .command))
        menu.addItem(item("Redo", #selector(ProseView.redo(_:)), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(ProseView.cut(_:)), "x", .command))
        menu.addItem(item("Copy", #selector(ProseView.copy(_:)), "c", .command))
        menu.addItem(item("Paste", #selector(ProseView.paste(_:)), "v", .command))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(ProseView.selectAll(_:)), "a", .command))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: EditorKeyModifiers) {
        self = []
        if modifiers.contains(.command) {
            insert(.command)
        }
        if modifiers.contains(.shift) {
            insert(.shift)
        }
    }
}
#endif
