#if canImport(UIKit)
import CoreGraphics
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

    var state: EditorState
    var layoutStore: IncrementalLayoutStore
    var layoutBox: LayoutBox?
    let geometryMapper = GeometryMapper()
    lazy var proseTokenizer = UITextInputStringTokenizer(textInput: self)
    /// The Canvas (ADR 0002); it owns all drawing — see CanvasView.
    let canvas = CanvasView()

    public init(document: Document, schema: Schema = .slice1) {
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        canvas.isUserInteractionEnabled = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Below the system selection chrome UITextInteraction installs.
        addSubview(canvas)
        // The system owns all selection chrome: caret, handles, loupe,
        // double-tap word select, edit menu.
        let textInteraction = UITextInteraction(for: .editable)
        textInteraction.textInput = self
        addInteraction(textInteraction)
        let checkboxTap = UITapGestureRecognizer(target: self, action: #selector(taskCheckboxTapped(_:)))
        checkboxTap.cancelsTouchesInView = false
        // Gated to checkbox hits only (see UIGestureRecognizerDelegate below).
        // An ungated tap recognizer competes with UITextInteraction's own tap
        // for direct touches and swallows tap-to-position-caret — pointer
        // clicks route through a separate path, so they keep working.
        checkboxTap.delegate = self
        addGestureRecognizer(checkboxTap)
        // Caret-follow is built in, so keyboard avoidance must be too —
        // otherwise revealing the caret can park it under the keyboard.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

    /// Hooks the drag gestures and reports whether one was found — the test
    /// seam pinning that the running OS still exposes the recognizer.
    @discardableResult
    func ensureSelectionDragHook() -> Bool {
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

    // MARK: - Layout and repaint

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

    private func relayout(changedRange: Range<Position>? = nil) {
        guard bounds.width > 0 else { return }
        layoutStore.width = bounds.width
        do {
            layoutBox = try layoutStore.layout(state.document, changedRange: changedRange)
        } catch is SchemaError {
            // A host handed the editor a document outside the Schema —
            // rejected input, not a broken invariant. Keep the previous
            // layout (or stay blank before a first layout).
        } catch {
            assertionFailure("relayout failed: \(error)")
        }
        canvas.layoutBox = layoutBox
        contentSize = layoutBox?.frame.size ?? .zero
    }

    /// Relayouts for the last transaction and invalidates only the region
    /// the edit can have moved (see CanvasView.editDirtyRect).
    private func relayoutAndDisplayEdit() {
        let previous = layoutBox
        relayout(changedRange: state.lastTransaction?.changedRange)
        setCanvasNeedsDisplay(CanvasView.editDirtyRect(
            from: previous,
            to: layoutBox,
            changedRange: state.lastTransaction?.changedRange,
            fallback: bounds
        ))
        scrollCaretToVisible()
        onStateChange?()
    }

    /// Reveals the Selection's head after local edits and keyboard caret
    /// moves, like UITextView. Programmatic document or selection changes
    /// never scroll; hosts reveal explicitly via scrollRangeToVisible.
    func scrollCaretToVisible() {
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

    // MARK: - Focus

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

    private func refreshSelectionDisplayGeometry() {
        for case let display as UITextSelectionDisplayInteraction in interactions {
            display.setNeedsSelectionUpdate()
        }
    }

    // MARK: - Editing

    public var hasText: Bool {
        state.document.totalTextCount > 0
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
        performEdit { try state.insertText(text) }
    }

    public func deleteBackward() {
        do {
            // At a block's text start: join into the previous sibling, or — when
            // it is the first child of a container — lift it out of the container.
            if try Commands.joinBackward().run(in: &state)
                || Commands.liftOutOfContainer().run(in: &state) {
                relayoutAndDisplayEdit()
                return
            }
        } catch {
            // The commands gate themselves, so a throw here is a real invariant
            // break, not a boundary condition.
            assertionFailure("backspace structural command failed: \(error)")
        }
        performEdit { try state.deleteBackward() }
    }

    /// Runs an edit between the input delegate's will/did notifications and
    /// repaints the edited region. A StepError is an edit the model cannot
    /// express yet (e.g. deleting a selection that spans blocks) — a designed
    /// no-op. Any other throw means a model invariant broke, surfaced in
    /// debug builds rather than silently swallowed.
    private func performEdit(_ edit: () throws -> Void) {
        inputDelegate?.textWillChange(self)
        do {
            try edit()
        } catch is StepError {
            // Unsupported edit: leave the document untouched.
        } catch {
            assertionFailure("edit failed: \(error)")
        }
        relayoutAndDisplayEdit()
        inputDelegate?.textDidChange(self)
    }

    func runCommand(_ command: Command) {
        // A command that didn't dispatch leaves a stale lastTransaction;
        // its dirty rect repaints an already-clean region, never too little.
        inputDelegate?.selectionWillChange(self)
        performEdit { _ = try command.run(in: &state) }
        refreshSelectionDisplayGeometry()
        inputDelegate?.selectionDidChange(self)
    }

    /// Clamps a Position to the Document's text range.
    func clamp(_ position: Position) -> Position {
        min(max(position, state.document.startTextPosition), state.document.endTextPosition)
    }

    // MARK: - Formatting commands (toolbar / key command surface)

    public func toggleHeading(level: Int = 1) {
        runCommand(Commands.toggleHeading(level: level))
    }

    public func toggleMark(_ mark: Mark) {
        runCommand(Commands.toggleMark(mark))
    }

    public func setLink(_ href: String) { runCommand(Commands.setLink(href: href)) }
    public func setTextAlign(_ value: String?) { runCommand(Commands.setTextAlign(value)) }
    public func setBlockType(headingLevel level: Int?) { runCommand(Commands.setBlockType(headingLevel: level)) }
    public func wrapInList(_ listType: String) { runCommand(Commands.wrapInList(listType)) }
    public func sinkListItem() { runCommand(Commands.sinkListItem()) }
    public func liftListItem() { runCommand(Commands.liftListItem()) }
    public func toggleTaskItemChecked() { runCommand(Commands.toggleTaskItemChecked()) }

    // MARK: - Active state (toolbar binding)

    public func isActive(_ mark: Mark) -> Bool { state.isActive(mark) }
    public var activeBlockType: String { state.activeBlockType }
    public var activeHeadingLevel: Int? { state.activeHeadingLevel }

    @objc private func taskCheckboxTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        toggleTaskCheckbox(at: gesture.location(in: self))
    }

    /// Toggles the `checked` attr of the task item whose checkbox sits under
    /// `point` (content space). Returns whether a checkbox was hit. Split from
    /// the gesture handler so the tap→toggle path is testable without UIKit
    /// gesture recognition.
    @discardableResult
    func toggleTaskCheckbox(at point: CGPoint) -> Bool {
        guard let position = taskCheckboxPosition(at: point) else { return false }
        state = EditorState(
            document: state.document,
            selection: TextSelection(anchor: position, head: position),
            lastTransaction: state.lastTransaction,
            typingMarks: state.typingMarks
        )
        toggleTaskItemChecked()
        return true
    }

    /// `point` is in content space — a UIScrollView's `bounds.origin` is its
    /// `contentOffset`, so `gesture.location(in: self)` already accounts for the
    /// scroll, exactly like the point handed to `closestPosition(to:)`.
    func taskCheckboxPosition(at point: CGPoint) -> Position? {
        guard let layoutBox else { return nil }

        func visit(_ box: LayoutBox) -> Position? {
            if box.node.type == "taskItem" {
                let size: CGFloat = 13
                let lineCenter = box.frame.minY + taskFirstLineCenterOffset(in: box)
                let rect = CGRect(x: box.frame.minX + 6, y: lineCenter - size / 2, width: size, height: size).insetBy(dx: -6, dy: -6)
                // `leaves` is populated on the root box only, so descend the
                // children to the item's own first leaf instead.
                if rect.contains(point), let firstLeaf = firstLeafBlock(in: box) {
                    return firstLeaf.positionRange.lowerBound + 1
                }
            }
            for child in box.children {
                if let position = visit(child) { return position }
            }
            return nil
        }

        return visit(layoutBox)
    }

    private func firstLeafBlock(in box: LayoutBox) -> LayoutBox? {
        if box.kind == .leafBlock { return box }
        for child in box.children {
            if let leaf = firstLeafBlock(in: child) { return leaf }
        }
        return nil
    }

    private func taskFirstLineCenterOffset(in box: LayoutBox) -> CGFloat {
        var node = box
        var offset: CGFloat = 0
        while node.kind == .container, let first = node.children.first {
            offset += first.frame.minY - node.frame.minY
            node = first
        }
        let lineHeight = node.lineFragments.first?.frame.height ?? 20
        return offset + lineHeight / 2
    }

    /// Called after any edit or selection change so a host toolbar can refresh
    /// its active-state highlighting.
    public var onStateChange: (() -> Void)?

    // MARK: - Input accessory

    private var customInputAccessoryView: UIView?

    /// A host-supplied accessory view (e.g. a formatting toolbar) shown above
    /// the keyboard. UIKit positions and animates it; the editor's keyboard
    /// avoidance already accounts for its height.
    public override var inputAccessoryView: UIView? { customInputAccessoryView }

    public func setInputAccessoryView(_ view: UIView?) {
        customInputAccessoryView = view
        if isFirstResponder { reloadInputViews() }
    }

    // MARK: - Edit menu

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
        // Pasting a URL onto a selection links the selection (Q6) instead of
        // replacing it; anything else replaces, splitting blocks at newlines.
        if !state.selection.isCollapsed, let href = LinkDetection.soleURL(in: text) {
            runCommand(Commands.setLink(href: href))
            return
        }
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

    // MARK: - Hardware keyboard

    public override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(toggleBoldFromKeyCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(toggleItalicFromKeyCommand)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(sinkListItemFromKeyCommand)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(liftListItemFromKeyCommand)),
        ]
        // Without priority, the system routes ⌘B/⌘I to the standard edit
        // actions instead of these commands.
        for command in commands {
            command.wantsPriorityOverSystemBehavior = true
        }
        return commands
    }

    public override func toggleBoldface(_ sender: Any?) {
        toggleMark(.bold)
    }

    public override func toggleItalics(_ sender: Any?) {
        toggleMark(.italic)
    }

    @objc private func toggleBoldFromKeyCommand() {
        toggleMark(.bold)
    }

    @objc private func toggleItalicFromKeyCommand() {
        toggleMark(.italic)
    }

    @objc private func sinkListItemFromKeyCommand() {
        sinkListItem()
    }

    @objc private func liftListItemFromKeyCommand() {
        liftListItem()
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
}

// MARK: - Checkbox gesture gating

extension ProseView: UIGestureRecognizerDelegate {
    /// The checkbox tap only tracks a touch that actually lands on a task
    /// checkbox. Everywhere else it declines the touch entirely, so it never
    /// arbitrates against UITextInteraction's tap and direct-touch
    /// caret positioning behaves like UITextView.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        taskCheckboxPosition(at: touch.location(in: self)) != nil
    }

    /// Even on a checkbox, let the system's recognizers run alongside ours so
    /// the gating above is the only thing the checkbox tap ever blocks.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
