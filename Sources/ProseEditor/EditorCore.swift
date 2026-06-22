import CoreGraphics
import ProseModel

public enum EditorEditAction {
    case copy
    case cut
    case paste
    case select
    case selectAll
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

    public init(document: Document, schema: Schema = .slice1) {
        self.schema = schema
        self.state = EditorState(document: document)
        self.layoutStore = IncrementalLayoutStore(schema: schema, width: 0)
    }

    public var document: Document {
        get { state.document }
        set {
            state = EditorState(document: newValue)
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
            revision: state.revision
        )
    }

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

    public func insertText(_ text: String) throws {
        try runAndNotifyIfTransactionApplied {
            try state.insertText(text)
        }
    }

    public func deleteBackward() throws {
        try runAndNotifyIfTransactionApplied {
            try state.deleteBackward()
        }
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
    /// report false and `undo()`/`redo()` are no-ops. A collaboration binding sets
    /// this while attached (ADR 0010) so the step stack never runs against
    /// concurrently-edited state, until collaborative undo (YUndoManager) lands.
    public var isUndoSuppressed = false

    public var canUndo: Bool { !isUndoSuppressed && state.history.canUndo }
    public var canRedo: Bool { !isUndoSuppressed && state.history.canRedo }

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
