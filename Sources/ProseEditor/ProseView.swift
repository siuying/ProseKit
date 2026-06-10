#if canImport(UIKit)
import CoreGraphics
import CoreText
import ProseModel
import UIKit

@MainActor public final class ProseView: UIView, UITextInput {
    public var document: Document {
        get { state.document }
        set {
            state = EditorState(document: newValue)
            relayout()
            setNeedsDisplay()
        }
    }

    public weak var inputDelegate: UITextInputDelegate?
    public var markedTextStyle: [NSAttributedString.Key: Any]?
    /// The pasteboard edit-menu actions read and write. Injectable because
    /// `UIPasteboard.general` is unavailable to unhosted test bundles.
    public var pasteboard: UIPasteboard = .general

    private var state: EditorState
    private var layoutStore: IncrementalLayoutStore
    private var layoutBox: LayoutBox?
    private let geometryMapper = GeometryMapper()
    private lazy var proseTokenizer = UITextInputStringTokenizer(textInput: self)

    public init(document: Document, schema: Schema = .slice1) {
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        contentMode = .redraw
        // The system owns all selection chrome: caret, handles, loupe,
        // double-tap word select, edit menu.
        let textInteraction = UITextInteraction(for: .editable)
        textInteraction.textInput = self
        addInteraction(textInteraction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    public override func draw(_ rect: CGRect) {
        guard let layoutBox, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        // CoreText draws in a bottom-left coordinate space; flip to UIKit's.
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.label.cgColor)
        for box in layoutBox.children {
            draw(block: box, in: context)
        }
        context.restoreGState()
    }

    private func relayout() {
        guard bounds.width > 0 else { return }
        layoutStore.width = bounds.width
        layoutBox = try? layoutStore.layout(state.document)
    }

    private func draw(block: LayoutBox, in context: CGContext) {
        for fragment in block.lineFragments {
            guard let typeset = fragment.typesetLine else { continue }
            let baseline = fragment.frame.minY + typeset.ascent
            context.textPosition = CGPoint(x: fragment.frame.minX, y: bounds.height - baseline)
            CTLineDraw(typeset.line, context)
        }
    }

    public override var canBecomeFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            setSelectionDisplayActivated(true)
        }
        return became
    }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setSelectionDisplayActivated(false)
        }
        return resigned
    }

    /// UITextInteraction only activates its selection display from its own
    /// tap gestures; programmatic focus must show the caret too, like
    /// UITextView does.
    private func setSelectionDisplayActivated(_ activated: Bool) {
        for case let display as UITextSelectionDisplayInteraction in interactions {
            display.isActivated = activated
            if activated {
                display.setNeedsSelectionUpdate()
            }
        }
    }

    public var hasText: Bool {
        !state.document.plainText.isEmpty
    }

    public func insertText(_ text: String) {
        // Every newline behaves like typing Return: it splits the block.
        let segments = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                runCommand(Commands.splitBlock())
            }
            if !segment.isEmpty || segments.count == 1 {
                insertPlainText(segment)
            }
        }
    }

    private func insertPlainText(_ text: String) {
        inputDelegate?.textWillChange(self)
        try? state.insertText(text)
        relayout()
        setNeedsDisplay()
        inputDelegate?.textDidChange(self)
    }

    public func deleteBackward() {
        if (try? Commands.joinBackward().run(in: &state)) == true {
            relayout()
            setNeedsDisplay()
            return
        }
        inputDelegate?.textWillChange(self)
        try? state.deleteBackward()
        relayout()
        setNeedsDisplay()
        inputDelegate?.textDidChange(self)
    }

    public var selectedTextRange: UITextRange? {
        get { ProseTextRange(anchor: state.selection.anchor, head: state.selection.head) }
        set {
            guard let range = newValue as? ProseTextRange else { return }
            inputDelegate?.selectionWillChange(self)
            state = EditorState(
                document: state.document,
                selection: range.textSelection,
                dispatchedTransactions: state.dispatchedTransactions
            )
            setNeedsDisplay()
            inputDelegate?.selectionDidChange(self)
        }
    }

    public var markedTextRange: UITextRange? { nil }

    public var beginningOfDocument: UITextPosition {
        ProseTextPosition(2)
    }

    public var endOfDocument: UITextPosition {
        ProseTextPosition(state.document.endTextPosition)
    }

    public var tokenizer: UITextInputTokenizer {
        proseTokenizer
    }

    public func text(in range: UITextRange) -> String? {
        guard let range = range as? ProseTextRange else { return nil }
        return plainText(from: min(range.anchor, range.head), to: max(range.anchor, range.head))
    }

    /// Plain text between two positions; block boundaries read as "\n" so
    /// ranges spanning blocks (Select All, tokenizer context) stay readable.
    private func plainText(from: Position, to: Position) -> String {
        var pieces: [String] = []
        for (index, block) in state.document.root.content.enumerated() {
            guard let textStart = state.document.position(ofTextInBlockAt: index) else { continue }
            let text = block.plainText
            let textEnd = textStart + text.count
            guard from <= textEnd, to >= textStart else { continue }
            let lower = max(from, textStart)
            let upper = min(to, textEnd)
            let start = text.index(text.startIndex, offsetBy: lower - textStart)
            let end = text.index(text.startIndex, offsetBy: upper - textStart)
            pieces.append(String(text[start..<end]))
        }
        return pieces.joined(separator: "\n")
    }

    public func replace(_ range: UITextRange, withText text: String) {
        guard let range = range as? ProseTextRange else { return }
        let from = min(range.anchor, range.head)
        let to = max(range.anchor, range.head)
        inputDelegate?.textWillChange(self)
        try? state.dispatch(Transaction(
            steps: [ReplaceStep(from: from, to: to, insertText: text)],
            selection: TextSelection(anchor: from + text.count, head: from + text.count),
            origin: .local
        ))
        relayout()
        setNeedsDisplay()
        inputDelegate?.textDidChange(self)
    }

    public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        if let markedText {
            insertText(markedText)
        }
    }

    public func unmarkText() {}

    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = fromPosition as? ProseTextPosition, let to = toPosition as? ProseTextPosition else {
            return nil
        }
        return ProseTextRange(anchor: from.position, head: to.position)
    }

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? ProseTextPosition else { return nil }
        return ProseTextPosition(clamp(position.position + offset))
    }

    public func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        guard let position = position as? ProseTextPosition, let layoutBox else { return nil }
        var current = position.position
        for _ in 0..<offset {
            switch direction {
            case .left: current = geometryMapper.position(before: current, in: layoutBox)
            case .right: current = geometryMapper.position(after: current, in: layoutBox)
            case .up: current = geometryMapper.position(above: current, in: layoutBox)
            case .down: current = geometryMapper.position(below: current, in: layoutBox)
            @unknown default: return nil
            }
        }
        return ProseTextPosition(clamp(current))
    }

    public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let lhs = position as? ProseTextPosition, let rhs = other as? ProseTextPosition else {
            return .orderedSame
        }
        if lhs.position == rhs.position { return .orderedSame }
        return lhs.position < rhs.position ? .orderedAscending : .orderedDescending
    }

    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let from = from as? ProseTextPosition, let to = toPosition as? ProseTextPosition else {
            return 0
        }
        return to.position - from.position
    }

    public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        direction == .left || direction == .up ? range.start : range.end
    }

    public func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let position = position as? ProseTextPosition else { return nil }
        let end = direction == .left ? position.position - 1 : position.position + 1
        return ProseTextRange(anchor: position.position, head: clamp(end))
    }

    public func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    public func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    public func firstRect(for range: UITextRange) -> CGRect {
        guard let range = range as? ProseTextRange else { return .zero }
        guard let layoutBox,
              let first = geometryMapper.selectionRects(for: range.textSelection, in: layoutBox).first else {
            return caretRect(for: ProseTextPosition(min(range.anchor, range.head)))
        }
        return first
    }

    public func caretRect(for position: UITextPosition) -> CGRect {
        guard let position = position as? ProseTextPosition, let layoutBox else { return .zero }
        return geometryMapper.caretRect(for: position.position, in: layoutBox)
    }

    public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let range = range as? ProseTextRange, let layoutBox else { return [] }
        let rects = geometryMapper.selectionRects(for: range.textSelection, in: layoutBox)
        return rects.enumerated().map { index, rect in
            ProseTextSelectionRect(
                rect: rect,
                containsStart: index == 0,
                containsEnd: index == rects.count - 1
            )
        }
    }

    public func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let layoutBox else {
            return ProseTextPosition(state.selection.head)
        }
        return ProseTextPosition(clamp(geometryMapper.closestPosition(to: point, in: layoutBox)))
    }

    public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        closestPosition(to: point)
    }

    public func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point) as? ProseTextPosition else { return nil }
        return ProseTextRange(anchor: position.position, head: clamp(position.position + 1))
    }

    public func toggleHeading(level: Int = 1) {
        runCommand(Commands.toggleHeading(level: level))
    }

    public func toggleCode() {
        runCommand(Commands.toggleMark(.code))
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return !state.selection.isCollapsed
        case #selector(paste(_:)):
            return pasteboard.hasStrings
        case #selector(select(_:)), #selector(selectAll(_:)):
            return hasText
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    public override func copy(_ sender: Any?) {
        guard let selectedTextRange, let text = text(in: selectedTextRange) else { return }
        pasteboard.string = text
    }

    public override func cut(_ sender: Any?) {
        guard let selectedTextRange, !selectedTextRange.isEmpty else { return }
        copy(sender)
        replace(selectedTextRange, withText: "")
    }

    public override func paste(_ sender: Any?) {
        guard let text = pasteboard.string else { return }
        // insertText replaces the current selection and splits blocks at newlines.
        insertText(text)
    }

    public override func select(_ sender: Any?) {
        let caret = ProseTextPosition(state.selection.head)
        guard let word = tokenizer.rangeEnclosingPosition(caret, with: .word, inDirection: .storage(.backward)) else {
            return
        }
        selectedTextRange = word
    }

    public override func selectAll(_ sender: Any?) {
        guard let begin = beginningOfDocument as? ProseTextPosition,
              let end = endOfDocument as? ProseTextPosition else { return }
        selectedTextRange = ProseTextRange(anchor: begin.position, head: end.position)
    }

    public override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(toggleBoldFromKeyCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(toggleItalicFromKeyCommand)),
        ]
        // Without priority, the system routes ⌘B/⌘I to the standard edit
        // actions instead of these commands.
        for command in commands {
            command.wantsPriorityOverSystemBehavior = true
        }
        return commands
    }

    public override func toggleBoldface(_ sender: Any?) {
        runCommand(Commands.toggleMark(.bold))
    }

    public override func toggleItalics(_ sender: Any?) {
        runCommand(Commands.toggleMark(.italic))
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, let direction = Self.arrowDirection(for: key) else {
            super.pressesBegan(presses, with: event)
            return
        }
        moveCaret(direction, extending: key.modifierFlags.contains(.shift))
    }

    private static func arrowDirection(for key: UIKey) -> UITextLayoutDirection? {
        switch key.keyCode {
        case .keyboardLeftArrow: .left
        case .keyboardRightArrow: .right
        case .keyboardUpArrow: .up
        case .keyboardDownArrow: .down
        default: nil
        }
    }

    private func moveCaret(_ direction: UITextLayoutDirection, extending: Bool) {
        let selection = state.selection

        if !extending, !selection.isCollapsed, direction == .left || direction == .right {
            // A plain horizontal arrow collapses the selection to its edge.
            let edge = direction == .left
                ? min(selection.anchor, selection.head)
                : max(selection.anchor, selection.head)
            selectedTextRange = ProseTextRange(anchor: edge, head: edge)
            return
        }

        guard let head = position(from: ProseTextPosition(selection.head), in: direction, offset: 1) as? ProseTextPosition else {
            return
        }
        selectedTextRange = ProseTextRange(anchor: extending ? selection.anchor : head.position, head: head.position)
    }

    private func clamp(_ position: Position) -> Position {
        min(max(position, 2), state.document.endTextPosition)
    }

    private func runCommand(_ command: Command) {
        inputDelegate?.textWillChange(self)
        _ = try? command.run(in: &state)
        relayout()
        setNeedsDisplay()
        inputDelegate?.textDidChange(self)
    }

    @objc private func toggleBoldFromKeyCommand() {
        runCommand(Commands.toggleMark(.bold))
    }

    @objc private func toggleItalicFromKeyCommand() {
        runCommand(Commands.toggleMark(.italic))
    }

}
#endif
