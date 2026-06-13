import ProseModel

/// A pattern watched at the caret during typing that, on match, rewrites the
/// just-typed text into structure (CONTEXT glossary: Input Rule). These are the
/// markdown block shortcuts; each fires when its `trigger` is the entire text
/// of the block up to the caret (i.e. typed at the block start).
///
/// The live wiring (running rules on each keystroke) and backspace-reverts-the-
/// rule behaviour are editor integration deferred to a later slice; the engine
/// and rule set are here and unit-tested directly.
public struct InputRule: Sendable {
    public let trigger: String
    let transform: @Sendable (inout EditorState, _ from: Position, _ to: Position) throws -> Void
}

public enum InputRules {
    /// The StarterKit block rules available today. List / blockquote / codeBlock
    /// / task rules join as those node types land (slices 10, 12, 14, 15).
    public static let starterKit: [InputRule] = headingRules

    /// `#`…`######` + space → heading of that level (Q5).
    static let headingRules: [InputRule] = (1...6).map { level in
        InputRule(trigger: String(repeating: "#", count: level) + " ") { state, from, to in
            // One Transaction: drop the trigger text, then promote the
            // (paragraph) block to a heading.
            try state.dispatch(Transaction(
                steps: [
                    ReplaceStep(from: from, to: to, insertText: ""),
                    SetBlockTypeStep(at: from, headingLevel: level),
                ],
                selection: TextSelection(anchor: from, head: from),
                origin: .local
            ))
        }
    }

    /// Fires the first rule whose `trigger` the collapsed caret has just
    /// completed at the start of its block. Returns whether a rule transformed
    /// the document.
    @discardableResult
    public static func apply(_ rules: [InputRule], to state: inout EditorState) throws -> Bool {
        guard state.selection.isCollapsed,
              let blockTextStart = state.document.blockTextStart(at: state.selection.head) else {
            return false
        }
        let head = state.selection.head
        let before = (try? state.document.text(from: blockTextStart, to: head)) ?? ""
        for rule in rules where before == rule.trigger {
            try rule.transform(&state, blockTextStart, head)
            return true
        }
        return false
    }
}
