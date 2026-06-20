import CoreGraphics
import ProseModel

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
            typingMarks: state.typingMarks
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
