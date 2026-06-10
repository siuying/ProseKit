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

    private var state: EditorState
    private var layoutStore: IncrementalLayoutStore
    private var layoutBox: LayoutBox?
    private lazy var proseTokenizer = UITextInputStringTokenizer(textInput: self)
    private var caretTimer: Timer?
    private var showsCaret = true

    public init(document: Document, schema: Schema = .slice1) {
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        contentMode = .redraw
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
        guard let layoutBox else { return }
        UIColor.label.setFill()
        for box in layoutBox.children {
            draw(block: box)
        }
        drawCaretIfNeeded()
    }

    private func relayout() {
        guard bounds.width > 0 else { return }
        layoutStore.width = bounds.width
        layoutBox = try? layoutStore.layout(state.document)
    }

    private func draw(block: LayoutBox) {
        let text = block.lineFragments.first?.text ?? ""
        let size: CGFloat = block.node.type == "heading" ? 28 : 17
        let weight: UIFont.Weight = block.node.type == "heading" ? .bold : .regular
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.label,
        ]
        text.draw(in: block.frame, withAttributes: attributes)
    }

    public override var canBecomeFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            startCaretBlink()
        }
        return became
    }

    public override func resignFirstResponder() -> Bool {
        caretTimer?.invalidate()
        caretTimer = nil
        return super.resignFirstResponder()
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = becomeFirstResponder()
        if let point = touches.first?.location(in: self),
           let position = closestPosition(to: point) as? ProseTextPosition {
            selectedTextRange = ProseTextRange(anchor: position.position, head: position.position)
        }
    }

    public var hasText: Bool {
        !state.document.plainText.isEmpty
    }

    public func insertText(_ text: String) {
        inputDelegate?.textWillChange(self)
        try? state.insertText(text)
        relayout()
        setNeedsDisplay()
        inputDelegate?.textDidChange(self)
    }

    public func deleteBackward() {
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
            state = EditorState(
                document: state.document,
                selection: range.textSelection,
                dispatchedTransactions: state.dispatchedTransactions
            )
            setNeedsDisplay()
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
        return try? state.document.text(from: min(range.anchor, range.head), to: max(range.anchor, range.head))
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
        self.position(from: position, offset: offset)
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
        return caretRect(for: ProseTextPosition(min(range.anchor, range.head)))
    }

    public func caretRect(for position: UITextPosition) -> CGRect {
        guard let position = position as? ProseTextPosition else { return .zero }
        let block = layoutBox?.children.first { $0.positionRange.contains(position.position) || $0.positionRange.upperBound == position.position }
        let frame = block?.frame ?? CGRect(x: 0, y: 0, width: bounds.width, height: 24)
        let textStart = block?.positionRange.lowerBound.advanced(by: 1) ?? 2
        let column = max(0, position.position - textStart)
        return CGRect(x: CGFloat(column) * 10, y: frame.minY, width: 2, height: frame.height)
    }

    public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        []
    }

    public func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let block = layoutBox?.children.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }) else {
            return ProseTextPosition(state.selection.head)
        }
        let column = max(0, Int((point.x / 10).rounded()))
        return ProseTextPosition(clamp(block.positionRange.lowerBound + 1 + column))
    }

    public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        closestPosition(to: point)
    }

    public func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point) as? ProseTextPosition else { return nil }
        return ProseTextRange(anchor: position.position, head: clamp(position.position + 1))
    }

    private func drawCaretIfNeeded() {
        guard isFirstResponder, showsCaret, state.selection.isCollapsed else { return }
        let rect = caretRect(for: ProseTextPosition(state.selection.head))
        UIColor.systemBlue.setFill()
        UIRectFill(rect)
    }

    private func clamp(_ position: Position) -> Position {
        min(max(position, 2), state.document.endTextPosition)
    }

    private func startCaretBlink() {
        caretTimer?.invalidate()
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.showsCaret.toggle()
                self?.setNeedsDisplay()
            }
        }
    }
}
#endif
