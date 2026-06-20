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

    public init(document: Document, schema: Schema = .slice1) {
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
        state = EditorState(
            document: state.document,
            selection: selection,
            lastTransaction: state.lastTransaction,
            typingMarks: state.typingMarks,
            history: state.history
        )
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
        try state.insertText(text)
    }

    public func deleteBackward() throws {
        try state.deleteBackward()
    }

    public var canUndo: Bool { state.history.canUndo }
    public var canRedo: Bool { state.history.canRedo }

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
        do {
            let ran = try state.undo()
            if ran {
                relayout(changedRange: state.lastTransaction?.changedRange)
            }
            return ran
        } catch {
            assertionFailure("undo failed: \(error)")
            return false
        }
    }

    @discardableResult
    public func redo() -> Bool {
        do {
            let ran = try state.redo()
            if ran {
                relayout(changedRange: state.lastTransaction?.changedRange)
            }
            return ran
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
        try command.run(in: &state)
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
