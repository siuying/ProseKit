import CoreGraphics
import ProseModel

public enum EditorEditAction {
    case copy
    case cut
    case paste
    case select
    case selectAll
}

/// Supplies CRDT-backed undo scoped to the local peer. A collaboration binding
/// adopts this so `EditorCore.undo()/redo()` revert only the local peer's changes
/// (as new CRDT operations) rather than running the solo step history against
/// concurrently-edited state (ADR 0010).
@MainActor public protocol CollaborativeUndoController: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undo() -> Bool
    func redo() -> Bool
}

@MainActor public final class EditorCore {
    public private(set) var state: EditorState
    public private(set) var layoutStore: IncrementalLayoutStore
    public private(set) var layoutBox: LayoutBox?
    public let geometryMapper = GeometryMapper()

    /// Fires once after each applied Transaction, after `state` is updated.
    public var didApplyTransaction: ((AppliedTransaction) -> Void)?

    /// The Schema this editor understands. Unknown node/mark types still load
    /// (ADR 0006) but a collaboration binding consults this to preserve them
    /// opaquely rather than reinterpreting them.
    public let schema: Schema

    /// When true, text typed through `insertText` is run past the StarterKit
    /// Input Rules (markdown shortcuts) after insertion. Defaults to enabled,
    /// matching Tiptap.
    ///
    /// Composition/marked text DOES currently reach this seam (the shells route
    /// `setMarkedText` through `insertText`); suppressing rules until input is
    /// committed is owned by the composition slice (Phase 5). Rules only fire at
    /// a caret that was collapsed before insertion — replacing a selection types
    /// plain.
    public var inputRulesEnabled = true

    public init(document: Document, schema: Schema = .slice1) {
        self.schema = schema
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
    }

    public var document: Document {
        get { state.document }
        set {
            state = EditorState(document: newValue, recordsHistory: !isCollaborativeUndoActive)
            relayout()
        }
    }

    public var selection: TextSelection { state.selection }
    public var lastTransaction: AppliedTransaction? { state.lastTransaction }

    public func setSelection(_ selection: TextSelection) {
        // Moving the caret ends any in-progress typing/deleting run so the next
        // edit starts a fresh undo step.
        var history = state.history
        history.breakCoalescing()
        state = EditorState(
            document: state.document,
            selection: selection,
            lastTransaction: state.lastTransaction,
            typingMarks: state.typingMarks,
            history: history,
            recordsHistory: state.recordsHistory,
            revision: state.revision
        )
        // Mirror the solo caret-jump coalescing boundary onto the collaborative
        // undo manager. (The CRDT manager may also split on its own capture
        // timeout, so grouping is close but not identical to solo mode.)
        onUndoCoalescingBreak?()
    }

    /// Fires when the solo undo history breaks typing coalescing (a caret jump),
    /// so a collaboration binding can stop the CRDT undo manager's capture at the
    /// same boundary.
    public var onUndoCoalescingBreak: (() -> Void)?

    private func runAndNotifyIfTransactionApplied<T>(_ work: () throws -> T) rethrows -> T {
        let revision = state.revision
        let result = try work()
        notifyIfApplied(since: revision)
        return result
    }

    private func notifyIfApplied(since revision: Int) {
        guard state.revision != revision, let applied = state.lastTransaction else { return }
        didApplyTransaction?(applied)
    }

    @discardableResult
    public func relayout(width: CGFloat? = nil, changedRange: Range<Position>? = nil) -> Bool {
        if let width {
            layoutStore.width = width
        }
        guard layoutStore.width > 0 else { return false }
        do {
            layoutBox = try layoutStore.layout(state.document, changedRange: changedRange)
            return true
        } catch is SchemaError {
            // Rejected host input: keep the previous layout, matching the
            // UIKit shell's old behavior.
            return false
        } catch {
            assertionFailure("relayout failed: \(error)")
            return false
        }
    }

    /// Inserts committed text and runs the StarterKit Input Rules (when
    /// enabled). Use the `applyingInputRules:` overload for input that must not
    /// trigger shortcuts — IME/marked text mid-composition and paste.
    public func insertText(_ text: String) throws {
        try insertText(text, applyingInputRules: inputRulesEnabled)
    }

    public func insertText(_ text: String, applyingInputRules: Bool) throws {
        try runAndNotifyIfTransactionApplied {
            try state.insertText(text)
            // Run markdown shortcuts on the resulting text. Like ProseMirror,
            // rules evaluate on the text before the caret after insertion,
            // regardless of whether a selection was replaced — so autocomplete /
            // replacement-range input can also complete a shortcut. The caret is
            // always collapsed after `insertText`; the guard documents intent.
            // The rule's own Transaction becomes `lastTransaction`, so the
            // follow-up relayout covers the converted block.
            if applyingInputRules, !text.isEmpty, state.selection.isCollapsed {
                try InputRules.apply(InputRules.starterKit, to: &state)
            }
        }
    }

    public func deleteBackward() throws {
        try runAndNotifyIfTransactionApplied {
            try state.deleteBackward()
        }
    }

    /// Reverts the most recent Input Rule to its literal Markdown if Backspace
    /// is pressed immediately after a shortcut fired. The view shells call this
    /// ahead of structural Backspace and plain deletion. Returns whether a rule
    /// was reverted.
    @discardableResult
    public func undoInputRule() -> Bool {
        var reverted = false
        runAndNotifyIfTransactionApplied {
            reverted = state.undoInputRule()
        }
        return reverted
    }

    /// Applies a remote-origin Transaction without recording local history.
    public func applyRemote(_ transaction: Transaction) {
        do {
            try runAndNotifyIfTransactionApplied {
                try state.dispatch(transaction, recordsHistory: false)
                relayout(changedRange: state.lastTransaction?.changedRange)
            }
        } catch {
            assertionFailure("applyRemote failed: \(error)")
            return
        }
    }

    /// When true, the solo step-based history is suppressed: `canUndo`/`canRedo`
    /// report false and `undo()`/`redo()` are no-ops. A fallback for a binding
    /// that cannot provide a `collaborativeUndoController` (ADR 0010).
    public var isUndoSuppressed = false {
        didSet { state.recordsHistory = !isCollaborativeUndoActive }
    }

    /// When set (by a collaboration binding), undo/redo delegate to CRDT-backed
    /// undo scoped to the local peer instead of the solo step history.
    public weak var collaborativeUndoController: (any CollaborativeUndoController)? {
        didSet { state.recordsHistory = !isCollaborativeUndoActive }
    }

    /// While collaborative undo is active (a controller is attached, or the
    /// suppression fallback is on) the solo step history is dormant: it neither
    /// records nor serves undo. So it cannot expose stale, remote-invalidated
    /// steps after `detach()` re-enables solo mode (ADR 0010).
    private var isCollaborativeUndoActive: Bool {
        collaborativeUndoController != nil || isUndoSuppressed
    }

    public var canUndo: Bool {
        if let controller = collaborativeUndoController { return controller.canUndo }
        return !isUndoSuppressed && state.history.canUndo
    }

    public var canRedo: Bool {
        if let controller = collaborativeUndoController { return controller.canRedo }
        return !isUndoSuppressed && state.history.canRedo
    }

    public func canPerformEditAction(_ action: EditorEditAction, pasteboardHasStrings: Bool) -> Bool {
        switch action {
        case .copy, .cut:
            return !state.selection.isCollapsed
        case .paste:
            return pasteboardHasStrings
        case .select, .selectAll:
            return state.document.totalTextCount > 0
        }
    }

    @discardableResult
    public func undo() -> Bool {
        if let controller = collaborativeUndoController { return controller.undo() }
        guard !isUndoSuppressed else { return false }
        do {
            return try runAndNotifyIfTransactionApplied {
                let ran = try state.undo()
                if ran {
                    relayout(changedRange: state.lastTransaction?.changedRange)
                }
                return ran
            }
        } catch {
            assertionFailure("undo failed: \(error)")
            return false
        }
    }

    @discardableResult
    public func redo() -> Bool {
        if let controller = collaborativeUndoController { return controller.redo() }
        guard !isUndoSuppressed else { return false }
        do {
            return try runAndNotifyIfTransactionApplied {
                let ran = try state.redo()
                if ran {
                    relayout(changedRange: state.lastTransaction?.changedRange)
                }
                return ran
            }
        } catch {
            assertionFailure("redo failed: \(error)")
            return false
        }
    }

    @discardableResult
    public func run(_ command: Command) -> Bool {
        do {
            let ran = try dispatch(command)
            if ran {
                relayout(changedRange: state.lastTransaction?.changedRange)
            }
            return ran
        } catch {
            assertionFailure("command failed: \(error)")
            return false
        }
    }

    @discardableResult
    public func dispatch(_ command: Command) throws -> Bool {
        try runAndNotifyIfTransactionApplied {
            try command.run(in: &state)
        }
    }

    public func caretRect(for position: Position) -> CGRect {
        guard let layoutBox else { return .zero }
        return geometryMapper.caretRect(for: position, in: layoutBox)
    }

    public func selectionRects(for selection: TextSelection) -> [CGRect] {
        guard let layoutBox else { return [] }
        return geometryMapper.selectionRects(for: selection, in: layoutBox)
    }

    public func closestPosition(to point: CGPoint) -> Position {
        guard let layoutBox else { return state.selection.head }
        return geometryMapper.closestPosition(to: point, in: layoutBox)
    }

    public func position(after position: Position) -> Position {
        guard let layoutBox else { return position }
        return geometryMapper.position(after: position, in: layoutBox)
    }

    public func position(before position: Position) -> Position {
        guard let layoutBox else { return position }
        return geometryMapper.position(before: position, in: layoutBox)
    }

    public func position(above position: Position) -> Position {
        guard let layoutBox else { return position }
        return geometryMapper.position(above: position, in: layoutBox)
    }

    public func position(below position: Position) -> Position {
        guard let layoutBox else { return position }
        return geometryMapper.position(below: position, in: layoutBox)
    }

    public func clamp(_ position: Position) -> Position {
        min(max(position, state.document.startTextPosition), state.document.endTextPosition)
    }
}
