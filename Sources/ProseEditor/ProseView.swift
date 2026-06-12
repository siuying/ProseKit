#if canImport(UIKit)
import CoreGraphics
import CoreText
import ProseModel
import UIKit

@MainActor public final class ProseView: UIScrollView, UITextInput {
    public var document: Document {
        get { state.document }
        set {
            state = EditorState(document: newValue)
            relayout()
            canvas.setNeedsDisplay()
        }
    }

    public weak var inputDelegate: UITextInputDelegate?
    public var markedTextStyle: [NSAttributedString.Key: Any]?
    /// Insets the Viewport for the keyboard automatically (a deliberate
    /// divergence from UITextView — built-in caret-follow needs it). Hosts
    /// that manage keyboard insets themselves opt out here.
    public var automaticallyAdjustsForKeyboard = true
    /// The pasteboard edit-menu actions read and write. Injectable because
    /// `UIPasteboard.general` is unavailable to unhosted test bundles.
    public var pasteboard: UIPasteboard = .general

    private var state: EditorState
    private var layoutStore: IncrementalLayoutStore
    private var layoutBox: LayoutBox?
    private let geometryMapper = GeometryMapper()
    private lazy var proseTokenizer = UITextInputStringTokenizer(textInput: self)
    /// The Canvas: a Viewport-sized paint surface repositioned on scroll
    /// (ADR 0002). It holds no document or geometry authority; selection
    /// chrome and hit-testing live on the scroll view, in content space.
    private let canvas = CanvasView()

    public init(document: Document, schema: Schema = .slice1) {
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        canvas.isUserInteractionEnabled = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawContent = { [weak self] rect, context in
            self?.drawCanvas(rect, in: context)
        }
        // Below the system selection chrome UITextInteraction installs.
        addSubview(canvas)
        // The system owns all selection chrome: caret, handles, loupe,
        // double-tap word select, edit menu.
        let textInteraction = UITextInteraction(for: .editable)
        textInteraction.textInput = self
        addInteraction(textInteraction)
        // Caret-follow is built in, so keyboard avoidance must be too —
        // otherwise revealing the caret can park it under the keyboard.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard automaticallyAdjustsForKeyboard,
              let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
            .cgRectValue else { return }
        // Screen space → local space keeps the math right while scrolled;
        // a dismissed keyboard sits below the view and overlaps nothing.
        let local = convert(endFrame, from: nil)
        let overlap = min(max(0, bounds.maxY - local.minY), bounds.height)
        contentInset.bottom = overlap
        verticalScrollIndicatorInsets.bottom = overlap
    }

    // MARK: - Selection-drag edge autoscroll

    /// UITextInteraction does not autoscroll when a selection-handle drag
    /// holds at the Viewport edge (verified on device 2026-06-12; see
    /// .scratch/scrolling/issues/01), so the view drives it: the system's
    /// range-adjustment pan is observed via addTarget, and while the drag
    /// sits in an edge band a display link scrolls the Viewport and extends
    /// the Selection head to the Position passing under the finger.
    private static let autoscrollBand: CGFloat = 44
    private static let autoscrollMaxStep: CGFloat = 8

    private var autoscrollStep: CGFloat = 0
    private var autoscrollDragLocation: CGPoint = .zero
    private var autoscrollDisplayLink: CADisplayLink?
    private var hookedDragGestures: Set<ObjectIdentifier> = []

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopSelectionDragAutoscroll()
        } else {
            hookSelectionDragGestures()
        }
    }

    /// The range-adjustment recognizer is the system's selection-handle
    /// drag. Matching by type name is the only public seam; the hook test
    /// pins that the running OS still exposes it.
    private func hookSelectionDragGestures() {
        for gesture in gestureRecognizers ?? [] {
            let id = ObjectIdentifier(gesture)
            guard !hookedDragGestures.contains(id),
                  String(describing: type(of: gesture)).contains("RangeAdjustment") else { continue }
            gesture.addTarget(self, action: #selector(selectionDragGestureChanged(_:)))
            hookedDragGestures.insert(id)
        }
    }

    var hasSelectionDragHook: Bool {
        hookSelectionDragGestures()
        return !hookedDragGestures.isEmpty
    }

    @objc private func selectionDragGestureChanged(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            updateSelectionDragAutoscroll(forDragAt: gesture.location(in: self))
        default:
            stopSelectionDragAutoscroll()
        }
    }

    /// `location` is in content space (the view's own coordinates). Inside
    /// the top/bottom edge band the scroll step ramps with penetration.
    func updateSelectionDragAutoscroll(forDragAt location: CGPoint) {
        autoscrollDragLocation = location
        let visible = bounds.inset(by: adjustedContentInset)
        let band = min(Self.autoscrollBand, visible.height / 3)
        if location.y > visible.maxY - band {
            autoscrollStep = Self.autoscrollMaxStep * min(1, (location.y - (visible.maxY - band)) / band)
        } else if location.y < visible.minY + band {
            autoscrollStep = -Self.autoscrollMaxStep * min(1, ((visible.minY + band) - location.y) / band)
        } else {
            autoscrollStep = 0
        }
        if autoscrollStep == 0 {
            stopSelectionDragAutoscroll()
        } else if autoscrollDisplayLink == nil, window != nil {
            let link = CADisplayLink(target: self, selector: #selector(selectionDragDisplayLinkFired))
            link.add(to: .main, forMode: .common)
            autoscrollDisplayLink = link
        }
    }

    @objc private func selectionDragDisplayLinkFired() {
        selectionDragAutoscrollTick()
    }

    /// One autoscroll frame: scroll by the current step (clamped to the
    /// content), carry the stationary finger's content-space location with
    /// the scroll, and extend the Selection head to the Position under it.
    func selectionDragAutoscrollTick() {
        guard autoscrollStep != 0, layoutBox != nil else { return }
        let minY = -adjustedContentInset.top
        let maxY = max(minY, contentSize.height + adjustedContentInset.bottom - bounds.height)
        let target = min(max(contentOffset.y + autoscrollStep, minY), maxY)
        guard target != contentOffset.y else { return }
        let delta = target - contentOffset.y
        contentOffset.y = target
        autoscrollDragLocation.y += delta
        if let head = closestPosition(to: autoscrollDragLocation) as? ProseTextPosition {
            selectedTextRange = ProseTextRange(anchor: state.selection.anchor, head: head.position)
        }
    }

    private func stopSelectionDragAutoscroll() {
        autoscrollStep = 0
        autoscrollDisplayLink?.invalidate()
        autoscrollDisplayLink = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Width is the only layout input UIKit owns; edits relayout
        // themselves with a Changed Range. UITextInteraction's selection
        // chrome dirties layout on every keystroke, and re-typesetting the
        // whole document here would defeat incremental relayout.
        if layoutBox == nil || layoutStore.width != bounds.width {
            relayout()
            canvas.setNeedsDisplay()
        }
        // bounds.origin is the contentOffset, so pinning the Canvas to bounds
        // keeps it over the Viewport; every move shows a different layout
        // slice, so the whole Canvas repaints.
        if canvas.frame != bounds {
            canvas.frame = bounds
            canvas.setNeedsDisplay()
        }
    }

    /// Paints the Layout Boxes intersecting the dirty region. `rect` is
    /// Canvas-local; blocks live in content space, offset by the Canvas's
    /// origin (the contentOffset). Internal so the culling-equivalence
    /// rendering test can drive it directly.
    func drawCanvas(_ rect: CGRect, in context: CGContext) {
        guard let layoutBox else { return }
        let origin = canvas.frame.origin
        // Outset for glyph overhang: descenders of a block ending just above
        // the dirty region still paint into it.
        let contentRect = rect
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: 0, dy: -Self.glyphOverhang)
        context.saveGState()
        // CoreText draws in a bottom-left coordinate space; flip to UIKit's
        // about the layout height, then shift content space into the Canvas.
        let flipHeight = layoutBox.frame.height
        context.textMatrix = .identity
        context.translateBy(x: -origin.x, y: -origin.y)
        context.translateBy(x: 0, y: flipHeight)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.label.cgColor)
        for box in layoutBox.children {
            // Blocks are y-ordered; everything past the dirty rect is clean.
            if box.frame.minY > contentRect.maxY { break }
            guard box.frame.intersects(contentRect) else { continue }
            draw(block: box, in: context, flippedAbout: flipHeight)
        }
        context.restoreGState()
    }

    private func relayout(changedRange: Range<Position>? = nil) {
        guard bounds.width > 0 else { return }
        layoutStore.width = bounds.width
        layoutBox = try? layoutStore.layout(state.document, changedRange: changedRange)
        contentSize = layoutBox?.frame.size ?? .zero
    }

    /// Relayouts for the last transaction and invalidates only the region
    /// the edit can have moved: the changed blocks' frames, extended to the
    /// document bottom when heights shift everything below. A wrong-too-big
    /// rect costs a repaint; a wrong-too-small rect leaves stale pixels, so
    /// every uncertain case falls back to the full bounds.
    private func relayoutAndDisplayEdit() {
        let previous = layoutBox
        relayout(changedRange: state.lastTransaction?.changedRange)
        setCanvasNeedsDisplay(Self.editDirtyRect(
            from: previous,
            to: layoutBox,
            changedRange: state.lastTransaction?.changedRange,
            fallback: bounds
        ))
        scrollCaretToVisible()
    }

    /// Reveals the Selection's head after local edits and keyboard caret
    /// moves, like UITextView. Programmatic document or selection changes
    /// never scroll; hosts reveal explicitly via scrollRangeToVisible.
    private func scrollCaretToVisible() {
        guard let layoutBox else { return }
        reveal(geometryMapper.caretRect(for: state.selection.head, in: layoutBox))
    }

    /// Scrolls the minimum amount to bring the range into the Viewport —
    /// the host's explicit reveal, mirroring UITextView's
    /// scrollRangeToVisible. Programmatic selection changes never scroll.
    public func scrollRangeToVisible(_ range: UITextRange) {
        guard let range = range as? ProseTextRange, let layoutBox else { return }
        let rects = geometryMapper.selectionRects(for: range.textSelection, in: layoutBox)
        let target = rects.reduce(CGRect.null) { $0.union($1) }
        reveal(target.isNull
            ? geometryMapper.caretRect(for: range.textSelection.head, in: layoutBox)
            : target)
    }

    /// Minimal scroll showing a content rect, with breathing room so the
    /// target isn't glued to the Viewport edge.
    private func reveal(_ contentRect: CGRect) {
        scrollRectToVisible(contentRect.insetBy(dx: 0, dy: -8), animated: false)
    }

    /// Invalidates a content-space rect on the Canvas, which is offset from
    /// content space by its origin (the contentOffset).
    private func setCanvasNeedsDisplay(_ contentRect: CGRect) {
        canvas.setNeedsDisplay(contentRect.offsetBy(
            dx: -canvas.frame.origin.x,
            dy: -canvas.frame.origin.y
        ))
    }

    static func editDirtyRect(
        from previous: LayoutBox?,
        to current: LayoutBox?,
        changedRange: Range<Position>?,
        fallback: CGRect
    ) -> CGRect {
        guard let previous, let current, let changedRange else { return fallback }
        // A collapsed range still names the edited spot (e.g. a no-op
        // command); widen it so the containing block is found.
        let range = changedRange.isEmpty
            ? changedRange.lowerBound..<(changedRange.lowerBound + 1)
            : changedRange
        var dirty: CGRect = .null
        for box in current.children {
            if box.positionRange.lowerBound >= range.upperBound { break }
            guard rangesIntersect(box.positionRange, range) else { continue }
            dirty = dirty.union(box.frame)
        }
        guard !dirty.isNull else { return fallback }

        // When total height or block count changes, every block below the
        // edit moved; both the old and new extent must repaint.
        if previous.frame.height != current.frame.height
            || previous.children.count != current.children.count {
            let bottom = max(previous.frame.maxY, current.frame.maxY)
            dirty = CGRect(
                x: 0, y: dirty.minY,
                width: max(fallback.width, dirty.width),
                height: bottom - dirty.minY
            )
        }
        // Full-width strip (fragment frames can be narrower than the view),
        // outset for glyph overhang at the strip edges.
        return CGRect(
            x: 0, y: dirty.minY,
            width: max(fallback.width, dirty.width),
            height: dirty.height
        ).insetBy(dx: 0, dy: -glyphOverhang)
    }

    /// How far glyphs may paint outside their block's frame (descenders,
    /// diacritics); dirty regions widen by this on both sides.
    private static let glyphOverhang: CGFloat = 2

    private func draw(block: LayoutBox, in context: CGContext, flippedAbout flipHeight: CGFloat) {
        for fragment in block.lineFragments {
            guard let typeset = fragment.typesetLine else { continue }
            let baseline = block.frame.minY + fragment.frame.minY + typeset.ascent
            context.textPosition = CGPoint(
                x: block.frame.minX + fragment.frame.minX,
                y: flipHeight - baseline
            )
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
        state.document.totalTextCount > 0
    }

    public func insertText(_ text: String) {
        NSLog("PROSE insertText '%@' sel=%d..%d", text, state.selection.anchor, state.selection.head)
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
        relayoutAndDisplayEdit()
        inputDelegate?.textDidChange(self)
    }

    public func deleteBackward() {
        NSLog("PROSE deleteBackward sel=%d..%d", state.selection.anchor, state.selection.head)
        if (try? Commands.joinBackward().run(in: &state)) == true {
            NSLog("PROSE deleteBackward joined; sel now %d..%d", state.selection.anchor, state.selection.head)
            relayoutAndDisplayEdit()
            return
        }
        inputDelegate?.textWillChange(self)
        try? state.deleteBackward()
        NSLog("PROSE deleteBackward plain; sel now %d..%d", state.selection.anchor, state.selection.head)
        relayoutAndDisplayEdit()
        inputDelegate?.textDidChange(self)
    }

    public var selectedTextRange: UITextRange? {
        get { ProseTextRange(anchor: state.selection.anchor, head: state.selection.head) }
        set {
            guard let range = newValue as? ProseTextRange else { return }
            NSLog("PROSE setSelectedTextRange %d..%d", range.anchor, range.head)
            inputDelegate?.selectionWillChange(self)
            state = EditorState(
                document: state.document,
                selection: range.textSelection,
                lastTransaction: state.lastTransaction,
                typingMarks: state.typingMarks
            )
            canvas.setNeedsDisplay()
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
    /// Materializes text only for blocks the range intersects — UIKit's
    /// keyboard calls this around every keystroke.
    private func plainText(from: Position, to: Position) -> String {
        let document = state.document
        var pieces: [String] = []
        guard let firstIndex = firstBlockIndex(withTextEndAtOrAfter: from) else { return "" }
        for index in firstIndex..<document.blockCount {
            guard let textStart = document.position(ofTextInBlockAt: index),
                  let count = document.textCount(ofBlockAt: index) else { continue }
            guard to >= textStart else { break }
            let text = document.root.content[index].plainText
            let lower = max(from, textStart)
            let upper = min(to, textStart + count)
            let start = text.index(text.startIndex, offsetBy: lower - textStart)
            let end = text.index(text.startIndex, offsetBy: upper - textStart)
            pieces.append(String(text[start..<end]))
        }
        return pieces.joined(separator: "\n")
    }

    /// First block whose text end (textStart + count) is >= position;
    /// binary search over the Document's block index.
    private func firstBlockIndex(withTextEndAtOrAfter position: Position) -> Int? {
        let document = state.document
        let count = document.blockCount
        guard count > 0 else { return nil }
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high) / 2
            let textEnd = document.position(ofTextInBlockAt: mid)! + document.textCount(ofBlockAt: mid)!
            if textEnd >= position { high = mid } else { low = mid + 1 }
        }
        let textEnd = document.position(ofTextInBlockAt: low)! + document.textCount(ofBlockAt: low)!
        return textEnd >= position ? low : nil
    }

    public func replace(_ range: UITextRange, withText text: String) {
        guard let range = range as? ProseTextRange else { return }
        let from = min(range.anchor, range.head)
        let to = max(range.anchor, range.head)
        NSLog("PROSE replace %d..%d with '%@' sel=%d..%d", from, to, text, state.selection.anchor, state.selection.head)
        inputDelegate?.textWillChange(self)
        try? state.dispatch(Transaction(
            steps: [ReplaceStep(from: from, to: to, insertText: text)],
            selection: TextSelection(anchor: from + text.count, head: from + text.count),
            origin: .local
        ))
        relayoutAndDisplayEdit()
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
        return ProseTextPosition(clamp(textPosition(position.position, movedByCharacterOffset: offset)))
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
        return characterOffset(of: to.position) - characterOffset(of: from.position)
    }

    /// Character offset into the "\n"-joined plain text for a document
    /// position. A block boundary is two positions (close + open token) but
    /// reads as one "\n", so position arithmetic and string arithmetic drift
    /// apart by one per boundary; UITextInput offset math must stay in
    /// character space to agree with text(in:). Inverse of
    /// position(atCharacterOffset:).
    private func characterOffset(of position: Position) -> Int {
        let document = state.document
        guard document.blockCount > 0 else { return 0 }
        guard let index = firstBlockIndex(withTextEndAtOrAfter: position) else {
            // Past every block: total characters plus one "\n" per boundary.
            return document.totalTextCount + document.blockCount - 1
        }
        let textStart = document.position(ofTextInBlockAt: index)!
        let charactersBefore = document.textCharacters(beforeBlockAt: index)! + index
        return charactersBefore + max(0, position - textStart)
    }

    private func position(atCharacterOffset offset: Int) -> Position {
        let document = state.document
        let count = document.blockCount
        guard count > 0 else { return document.endTextPosition }
        // First block whose joined-character end (charStart + index + textCount)
        // is >= offset; the "\n" before a block maps to the previous block's end.
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if characterEnd(ofBlockAt: mid, in: document) >= offset { high = mid } else { low = mid + 1 }
        }
        guard characterEnd(ofBlockAt: low, in: document) >= offset else {
            return document.endTextPosition
        }
        let textStart = document.position(ofTextInBlockAt: low)!
        let characterStart = document.textCharacters(beforeBlockAt: low)! + low
        return textStart + max(0, offset - characterStart)
    }

    /// Offset just past the block's text in "\n"-joined character space.
    private func characterEnd(ofBlockAt index: Int, in document: Document) -> Int {
        document.textCharacters(beforeBlockAt: index)! + index + document.textCount(ofBlockAt: index)!
    }

    private func textPosition(_ position: Position, movedByCharacterOffset offset: Int) -> Position {
        if offset == 0 { return position }
        return offset > 0
            ? textPosition(position, movedForwardByCharacterOffset: offset)
            : textPosition(position, movedBackwardByCharacterOffset: -offset)
    }

    private func textPosition(_ position: Position, movedForwardByCharacterOffset offset: Int) -> Position {
        var current = position
        var remaining = offset

        while remaining > 0 {
            guard let info = state.document.blockInfo(containing: current) else {
                return state.document.endTextPosition
            }
            let textStart = info.start + 1
            let textEnd = textStart + info.node.plainText.count
            let distanceInsideBlock = max(0, textEnd - current)
            if remaining <= distanceInsideBlock {
                return current + remaining
            }
            remaining -= distanceInsideBlock
            guard state.document.root.content.indices.contains(info.index + 1),
                  let nextTextStart = state.document.position(ofTextInBlockAt: info.index + 1) else {
                return textEnd
            }
            remaining -= 1
            current = nextTextStart
        }

        return current
    }

    private func textPosition(_ position: Position, movedBackwardByCharacterOffset offset: Int) -> Position {
        var current = position
        var remaining = offset

        while remaining > 0 {
            guard let info = state.document.blockInfo(containing: current) else {
                return 2
            }
            let textStart = info.start + 1
            let distanceInsideBlock = max(0, current - textStart)
            if remaining <= distanceInsideBlock {
                return current - remaining
            }
            remaining -= distanceInsideBlock
            guard info.index > 0,
                  let previousTextStart = state.document.position(ofTextInBlockAt: info.index - 1) else {
                return textStart
            }
            remaining -= 1
            let previous = state.document.root.content[info.index - 1]
            current = previousTextStart + previous.plainText.count
        }

        return current
    }

    public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        direction == .left || direction == .up ? range.start : range.end
    }

    public func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let position = position as? ProseTextPosition,
              let end = self.position(from: position, offset: direction == .left ? -1 : 1) as? ProseTextPosition else {
            return nil
        }
        return ProseTextRange(anchor: position.position, head: end.position)
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

    public func toggleBold() {
        runCommand(Commands.toggleMark(.bold))
    }

    public func toggleItalic() {
        runCommand(Commands.toggleMark(.italic))
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

    /// Keyboard caret movement (arrow keys). Internal so tests can drive it:
    /// UIPress events cannot be synthesized.
    func moveCaret(_ direction: UITextLayoutDirection, extending: Bool) {
        let selection = state.selection

        if !extending, !selection.isCollapsed, direction == .left || direction == .right {
            // A plain horizontal arrow collapses the selection to its edge.
            let edge = direction == .left
                ? min(selection.anchor, selection.head)
                : max(selection.anchor, selection.head)
            selectedTextRange = ProseTextRange(anchor: edge, head: edge)
            scrollCaretToVisible()
            return
        }

        guard let head = position(from: ProseTextPosition(selection.head), in: direction, offset: 1) as? ProseTextPosition else {
            return
        }
        selectedTextRange = ProseTextRange(anchor: extending ? selection.anchor : head.position, head: head.position)
        scrollCaretToVisible()
    }

    private func clamp(_ position: Position) -> Position {
        min(max(position, 2), state.document.endTextPosition)
    }

    private func runCommand(_ command: Command) {
        inputDelegate?.textWillChange(self)
        _ = try? command.run(in: &state)
        // A command that didn't dispatch leaves a stale lastTransaction;
        // its dirty rect repaints an already-clean region, never too little.
        relayoutAndDisplayEdit()
        inputDelegate?.textDidChange(self)
    }

    @objc private func toggleBoldFromKeyCommand() {
        toggleBold()
    }

    @objc private func toggleItalicFromKeyCommand() {
        toggleItalic()
    }

}

/// The Canvas's view: a dumb paint surface. All drawing logic stays in
/// ProseView; the Canvas only forwards its dirty rects.
@MainActor private final class CanvasView: UIView {
    var drawContent: ((CGRect, CGContext) -> Void)?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawContent?(rect, context)
    }
}
#endif
