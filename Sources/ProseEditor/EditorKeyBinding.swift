import ProseModel

public struct EditorKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = EditorKeyModifiers(rawValue: 1 << 0)
    public static let shift = EditorKeyModifiers(rawValue: 1 << 1)
}

public struct EditorKeyBinding: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case character(String)
        case tab

        /// The platform key-equivalent string shared by the AppKit menus and
        /// the UIKit key commands, so every binding maps its key one way.
        public var keyEquivalent: String {
            switch self {
            case let .character(character):
                return character
            case .tab:
                return "\t"
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case toggleBold
        case toggleItalic
        case sinkListItem
        case liftListItem
    }

    public let key: Key
    public let modifiers: EditorKeyModifiers
    public let action: Action

    public init(key: Key, modifiers: EditorKeyModifiers, action: Action) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }
}

extension EditorKeyBinding.Action {
    var command: Command {
        switch self {
        case .toggleBold:
            Commands.toggleMark(.bold)
        case .toggleItalic:
            Commands.toggleMark(.italic)
        case .sinkListItem:
            Commands.sinkListItem()
        case .liftListItem:
            Commands.liftListItem()
        }
    }
}

extension EditorCore {
    nonisolated public static let sharedKeyBindings: [EditorKeyBinding] = [
        EditorKeyBinding(key: .character("b"), modifiers: .command, action: .toggleBold),
        EditorKeyBinding(key: .character("i"), modifiers: .command, action: .toggleItalic),
        EditorKeyBinding(key: .tab, modifiers: [], action: .sinkListItem),
        EditorKeyBinding(key: .tab, modifiers: .shift, action: .liftListItem),
    ]

    public func keyBinding(for key: EditorKeyBinding.Key, modifiers: EditorKeyModifiers) -> EditorKeyBinding? {
        Self.sharedKeyBindings.first { $0.key == key && $0.modifiers == modifiers }
    }

    @discardableResult
    public func runKeyBindingAction(_ action: EditorKeyBinding.Action) -> Bool {
        run(action.command)
    }
}
