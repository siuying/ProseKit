#if canImport(UIKit)
import CoreGraphics
import ProseModel
import UIKit

@MainActor public final class ProseView: UIScrollView, UITextInput {
    public var document: Document {
        get { core.document }
        set {
            core.document = newValue
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
    public var pasteboard: Pasteboard = UIPasteboard.general

    let core: EditorCore
    var state: EditorState { core.state }
    var layoutStore: IncrementalLayoutStore { core.layoutStore }
    var layoutBox: LayoutBox? { core.layoutBox }
    var geometryMapper: GeometryMapper { core.geometryMapper }
    lazy var proseTokenizer = UITextInputStringTokenizer(textInput: self)
    /// The Canvas (ADR 0002); it owns all drawing — see CanvasView.
    let canvas = CanvasView()
    /// The task-checkbox tap; kept so the gesture delegate can gate only this
    /// recognizer and never the scroll view's own pan/touch gestures, whose
    /// delegate is also `self` (a UIScrollView is its own gestures' delegate).
    private var checkboxTap: UITapGestureRecognizer?

    public init(document: Document, schema: Schema = .slice1) {
        self.core = EditorCore(document: document, schema: schema)
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
        self.checkboxTap = checkboxTap
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
        // The keyboard frame is in its screen's coordinate space. Convert
        // through this view's own screen (an intra-screen conversion) so the
        // math stays right while scrolled and a dismissed keyboard — sitting
        // below the view — overlaps nothing. convert(_:from: nil) instead lets
        // UIKit reach for the keyboard's UIScreen, which on iPad multitasking
        // (iPadOS 16.1+) is a different UIScreen instance than the window's and
        // logs "Invalid UIScreen coordinate space conversion".
        let local = window.map { $0.screen.coordinateSpace.convert(endFrame, to: self) }
            ?? convert(endFrame, from: nil)
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
        core.relayout(width: bounds.width, changedRange: changedRange)
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
        performEdit { try core.insertText(text) }
    }

    public func deleteBackward() {
        // Backspace immediately after a shortcut reverts it to the literal
        // Markdown, ahead of any structural join or plain deletion. Routed
        // through performEdit so the input delegate sees text will/did change.
        if core.state.appliedInputRule != nil {
            performEdit { _ = core.undoInputRule() }
            return
        }
        do {
            // At a block's text start: join into the previous sibling, or — when
            // it is the first child of a container — lift it out of the container.
            if try core.dispatch(Commands.joinBackward())
                || core.dispatch(Commands.liftOutOfContainer()) {
                relayoutAndDisplayEdit()
                return
            }
        } catch {
            // The commands gate themselves, so a throw here is a real invariant
            // break, not a boundary condition.
            assertionFailure("backspace structural command failed: \(error)")
        }
        performEdit { try core.deleteBackward() }
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
        let selectionBefore = state.selection
        inputDelegate?.selectionWillChange(self)
        performEdit { _ = try core.dispatch(command) }
        // Block formatting (heading/list/align) keeps the *same* selection range
        // but reflows the glyphs under it, so UIKit — which treats an unchanged
        // range as nothing to re-measure — must be forced to refresh the
        // selection geometry. A command that *moves* the caret (e.g. splitBlock)
        // does not: the range change UIKit observes via selectionDidChange
        // refreshes it on the cheap path keyboard caret moves take. Forcing it
        // there too lagged ~1s when the command ran inside an input transaction
        // (e.g. splitBlock per newline during a multi-line paste); see
        // docs/research/2026-06-14-live-keyboard-responder-performance.md
        // finding 1 and performEditMenuEdit.
        if state.selection == selectionBefore {
            refreshSelectionDisplayGeometry()
        }
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

    public func removeMark(type: String) { runCommand(Commands.removeMark(type: type)) }
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
    public var activeListType: String? { state.activeListType }
    public var canSinkListItem: Bool { state.canSinkListItem }
    public var canLiftListItem: Bool { state.canLiftListItem }
    public var canToggleTaskItemChecked: Bool { state.canToggleTaskItemChecked }
    public var canSetLink: Bool { state.canSetLink }
    public var hasHighlight: Bool { state.hasHighlight }

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
        core.setSelection(TextSelection(anchor: position, head: position))
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
                let size: CGFloat = 15
                let lineCenter = box.frame.minY + taskFirstLineCenterOffset(in: box)
                let rect = CGRect(x: box.frame.minX + 5, y: lineCenter - size / 2, width: size, height: size).insetBy(dx: -6, dy: -6)
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
        case #selector(copy(_:)):
            return core.canPerformEditAction(.copy, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(cut(_:)):
            return core.canPerformEditAction(.cut, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(paste(_:)):
            return core.canPerformEditAction(.paste, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(select(_:)):
            return core.canPerformEditAction(.select, pasteboardHasStrings: pasteboard.hasStrings)
        case #selector(selectAll(_:)):
            return core.canPerformEditAction(.selectAll, pasteboardHasStrings: pasteboard.hasStrings)
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
        performEditMenuEdit { replace(selectedTextRange, withText: "") }
    }

    public override func paste(_ sender: Any?) {
        guard let text = pasteboard.string else { return }
        // Pasting a URL onto a selection links the selection (Q6) instead of
        // replacing it; anything else replaces, splitting blocks at newlines.
        if !state.selection.isCollapsed, let href = LinkDetection.soleURL(in: text) {
            runCommand(Commands.setLink(href: href))
            return
        }
        performEditMenuEdit { insertText(text) }
    }

    /// Runs a programmatic edit-menu edit (cut/paste) that moves the selection
    /// and tells the input delegate it moved. Typed text gets this for free —
    /// UIKit drives the insertion and updates the caret/selection display
    /// itself — but an edit-menu action does not, so `insertText`'s
    /// `performEdit` (which only brackets the text change) would leave the
    /// caret, or after a cut the old selection highlight, stranded where the
    /// removed text used to be.
    ///
    /// The delegate notifications alone are enough: UIKit re-queries the
    /// selection geometry off the back of them, the same cheap path keyboard
    /// caret moves take. Forcing `setNeedsSelectionUpdate()` here instead made
    /// paste lag ~1s — the forced selection-display work tangles with SwiftUI
    /// async rendering inside the input transaction (see
    /// docs/research/2026-06-14-live-keyboard-responder-performance.md, finding
    /// 1). Let UIKit schedule the display update.
    private func performEditMenuEdit(_ edit: () -> Void) {
        inputDelegate?.selectionWillChange(self)
        edit()
        inputDelegate?.selectionDidChange(self)
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
        let commands = EditorCore.sharedKeyBindings.map { binding in
            UIKeyCommand(
                input: binding.key.keyEquivalent,
                modifierFlags: Self.uiModifierFlags(for: binding.modifiers),
                action: Self.uiAction(for: binding.action)
            )
        }
        // Without priority, the system routes ⌘B/⌘I to the standard edit
        // actions instead of these commands.
        for command in commands {
            command.wantsPriorityOverSystemBehavior = true
        }
        return commands
    }

    public override func toggleBoldface(_ sender: Any?) {
        runKeyBindingAction(.toggleBold)
    }

    public override func toggleItalics(_ sender: Any?) {
        runKeyBindingAction(.toggleItalic)
    }

    @objc private func toggleBoldFromKeyCommand() {
        runKeyBindingAction(.toggleBold)
    }

    @objc private func toggleItalicFromKeyCommand() {
        runKeyBindingAction(.toggleItalic)
    }

    @objc private func sinkListItemFromKeyCommand() {
        runKeyBindingAction(.sinkListItem)
    }

    @objc private func liftListItemFromKeyCommand() {
        runKeyBindingAction(.liftListItem)
    }

    private func runKeyBindingAction(_ action: EditorKeyBinding.Action) {
        runCommand(action.command)
    }

    private static func uiModifierFlags(for modifiers: EditorKeyModifiers) -> UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) {
            flags.insert(.command)
        }
        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        return flags
    }

    private static func uiAction(for action: EditorKeyBinding.Action) -> Selector {
        switch action {
        case .toggleBold:
            return #selector(toggleBoldFromKeyCommand)
        case .toggleItalic:
            return #selector(toggleItalicFromKeyCommand)
        case .sinkListItem:
            return #selector(sinkListItemFromKeyCommand)
        case .liftListItem:
            return #selector(liftListItemFromKeyCommand)
        }
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, let direction = Self.arrowDirection(for: key) else {
            super.pressesBegan(presses, with: event)
            return
        }
        let extending = key.modifierFlags.contains(.shift)
        // Option+Left/Right moves by word like UITextView; the modifier is
        // meaningless on the vertical arrows, so those stay single-step.
        if key.modifierFlags.contains(.alternate), direction == .left || direction == .right {
            moveCaretByWord(direction, extending: extending)
        } else {
            moveCaret(direction, extending: extending)
        }
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

    /// Word-granular caret movement (Option+Arrow), matching UITextView:
    /// Option+Right lands at the end of the next word, Option+Left at the start
    /// of the previous one. Internal so tests can drive it: UIPress events
    /// cannot be synthesized.
    func moveCaretByWord(_ direction: UITextLayoutDirection, extending: Bool) {
        let selection = state.selection
        guard let head = wordTarget(from: ProseTextPosition(selection.head), direction: direction) else {
            // No further word boundary (already at the document edge): take the
            // single geometric step so the key never feels dead.
            moveCaret(direction, extending: extending)
            return
        }
        selectedTextRange = ProseTextRange(anchor: extending ? selection.anchor : head.position, head: head.position)
        scrollCaretToVisible()
    }

    /// The Position Option+Arrow targets. The system tokenizer reports a
    /// boundary at every word edge — both starts and ends — so a single hop
    /// would stop on the near edge of the gap between words. UITextView instead
    /// jumps over it: rightward to the next word *end*, and leftward to the
    /// previous word *start*. Those far edges are exactly the ones the
    /// tokenizer flags as a boundary in the travel direction (verified on the
    /// simulator: a word end answers `.forward`, a word start answers
    /// `.backward`), so walk boundaries until one does.
    private func wordTarget(from position: ProseTextPosition, direction: UITextLayoutDirection) -> ProseTextPosition? {
        let step: UITextStorageDirection = direction == .left ? .backward : .forward
        var current: UITextPosition = position
        var advanced = false
        while let next = tokenizer.position(from: current, toBoundary: .word, inDirection: .storage(step)) {
            current = next
            advanced = true
            if tokenizer.isPosition(next, atBoundary: .word, inDirection: .storage(step)) {
                return next as? ProseTextPosition
            }
        }
        // Boundaries ran out before a word edge (e.g. trailing whitespace):
        // settle at the furthest one reached, which is the document edge.
        return advanced ? current as? ProseTextPosition : nil
    }
}

// MARK: - Checkbox gesture gating

extension ProseView: UIGestureRecognizerDelegate {
    /// The checkbox tap only tracks a touch that actually lands on a task
    /// checkbox. Everywhere else it declines the touch entirely, so it never
    /// arbitrates against UITextInteraction's tap and direct-touch
    /// caret positioning behaves like UITextView.
    ///
    /// Self is also the delegate of the scroll view's own pan/touch gestures
    /// (a UIScrollView is its own gestures' delegate), so this must answer for
    /// the checkbox tap alone and defer to the default (accept) for the rest —
    /// gating the scroll pan here would stop scrolling everywhere off a
    /// checkbox.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === checkboxTap else { return true }
        return taskCheckboxPosition(at: touch.location(in: self)) != nil
    }

    /// Even on a checkbox, let the system's recognizers run alongside ours so
    /// the gating above is the only thing the checkbox tap ever blocks. Scoped
    /// to the checkbox tap so the scroll view's own gesture relationships are
    /// left at their defaults.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === checkboxTap || other === checkboxTap
    }
}
#endif
