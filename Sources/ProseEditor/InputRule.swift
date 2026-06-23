import ProseModel

/// A match produced by an Input Rule's finder. Ranges are measured in the same
/// character units as Document text positions (integer offsets into the current
/// block's text before the caret), so they compose directly with `Position`
/// math via `blockTextStart + offset`.
///
/// Mirrors the result of Tiptap's input-rule finder: `range` is the whole
/// matched span (delimiters included), `contentRange` is the inner content a
/// mark rule formats (`abc` within `*abc*`), `text` is the literal matched
/// string (used for immediate undo later), and `data` carries rule-specific
/// extras such as a heading level.
public struct InputRuleMatch: Sendable, Equatable {
    public var range: Range<Int>
    public var contentRange: Range<Int>?
    public var text: String
    public var data: [String: JSONValue]

    public init(
        range: Range<Int>,
        contentRange: Range<Int>? = nil,
        text: String,
        data: [String: JSONValue] = [:]
    ) {
        self.range = range
        self.contentRange = contentRange
        self.text = text
        self.data = data
    }
}

/// A pattern watched at the caret during typing that, on match, rewrites the
/// just-typed text into structure or formatting (CONTEXT glossary: Input Rule).
///
/// A rule is a `find` closure (scans the text before the caret and returns an
/// `InputRuleMatch`, or nil) plus a `transform` that edits the document for that
/// match. Exact block triggers are the common case and have a convenience
/// constructor (`exactBlock`); inline mark rules use suffix finders that land in
/// later slices.
///
/// The live wiring (running rules on each keystroke) and backspace-reverts-the-
/// rule behaviour are editor integration deferred to later slices; the engine
/// and rule set are here and unit-tested directly.
public struct InputRule: Sendable {
    /// Scans `textBeforeCaret` (the current block's text from its start to the
    /// collapsed caret) and returns the match to transform, or nil.
    public let find: @Sendable (_ textBeforeCaret: String) -> InputRuleMatch?
    /// Edits the document for a match. `blockTextStart` is the Position of the
    /// current block's text start, so the matched span is
    /// `blockTextStart + match.range.lowerBound ..< blockTextStart + match.range.upperBound`.
    let transform: @Sendable (inout EditorState, _ match: InputRuleMatch, _ blockTextStart: Position) throws -> Void

    public init(
        find: @escaping @Sendable (_ textBeforeCaret: String) -> InputRuleMatch?,
        transform: @escaping @Sendable (inout EditorState, _ match: InputRuleMatch, _ blockTextStart: Position) throws -> Void
    ) {
        self.find = find
        self.transform = transform
    }

    /// An inline mark rule for a symmetric delimiter (e.g. `*`, `**`, `` ` ``,
    /// `~~`). A suffix finder matches `delimiter + content + delimiter` ending at
    /// the caret (not consuming any preceding text), then the transform deletes
    /// both delimiters and adds `mark` over the content — ProseKit's analogue of
    /// Tiptap's `markInputRule`. Mark coexistence still flows through
    /// `MarkRules`/`AddMarkStep`.
    static func mark(
        delimiter: String,
        mark: Mark,
        rejectWhitespaceOnlyContent: Bool = true,
        rejectOpeningPrecededBy: Character? = nil
    ) -> InputRule {
        InputRule(
            find: { before in
                markSuffixMatch(
                    in: before,
                    delimiter: delimiter,
                    rejectWhitespaceOnlyContent: rejectWhitespaceOnlyContent,
                    rejectOpeningPrecededBy: rejectOpeningPrecededBy
                )
            },
            transform: { state, match, blockTextStart in
                let dlen = delimiter.count
                let s = blockTextStart + match.range.lowerBound
                let e = blockTextStart + match.range.upperBound
                let openEnd = s + dlen
                let closeStart = e - dlen
                // Steps apply sequentially: drop the closing delimiter, then the
                // opening one (which shifts the content left by `dlen`), then add
                // the Mark over the shifted content. Caret lands after it.
                let markedEnd = closeStart - dlen
                try state.dispatch(Transaction(
                    steps: [
                        ReplaceStep(from: closeStart, to: e, insertText: ""),
                        ReplaceStep(from: s, to: openEnd, insertText: ""),
                        AddMarkStep(from: s, to: markedEnd, mark: mark),
                    ],
                    selection: TextSelection(anchor: markedEnd, head: markedEnd),
                    origin: .local
                ))
                // The caret now sits at the end of the marked run; without this
                // the next typed character would inherit the Mark. Clear it so
                // typing after the shortcut is plain (ProseMirror parity).
                state.recordPendingMarkRemovals([mark])
            }
        )
    }

    /// Finds `delimiter + content + delimiter` anchored at the end of `text`,
    /// returning the matched suffix span (delimiters included) and its inner
    /// content range. Content may not contain a delimiter character and must be
    /// non-empty; `rejectWhitespaceOnlyContent` and `rejectOpeningPrecededBy`
    /// add the per-rule guards (whitespace-only content, a preceding backtick).
    static func markSuffixMatch(
        in text: String,
        delimiter: String,
        rejectWhitespaceOnlyContent: Bool,
        rejectOpeningPrecededBy: Character?
    ) -> InputRuleMatch? {
        let chars = Array(text)
        let delim = Array(delimiter)
        let dlen = delim.count
        let n = chars.count
        // Need both delimiters plus at least one content character.
        guard dlen > 0, n >= 2 * dlen + 1 else { return nil }
        // Must end with the delimiter.
        guard Array(chars.suffix(dlen)) == delim else { return nil }
        let closeStart = n - dlen
        // Content carries no delimiter character, so scan left from the closing
        // delimiter until the first delimiter character: that is the opening
        // delimiter's final character.
        let delimChars = Set(delim)
        var i = closeStart - 1
        while i >= 0, !delimChars.contains(chars[i]) { i -= 1 }
        guard i >= 0 else { return nil }
        let openEnd = i + 1
        let openStart = openEnd - dlen
        guard openStart >= 0, Array(chars[openStart..<openEnd]) == delim else { return nil }
        let content = Array(chars[openEnd..<closeStart])
        guard !content.isEmpty else { return nil }
        if rejectWhitespaceOnlyContent, content.allSatisfy(\.isWhitespace) { return nil }
        if let pc = rejectOpeningPrecededBy, openStart - 1 >= 0, chars[openStart - 1] == pc {
            return nil
        }
        return InputRuleMatch(
            range: openStart..<n,
            contentRange: openEnd..<closeStart,
            text: String(chars[openStart..<n])
        )
    }

    /// An exact block trigger: matches only when the entire text before the
    /// caret equals `trigger` (i.e. typed at the block start). The transform is
    /// expressed in absolute `from`/`to` positions for convenience, matching the
    /// historic rule shape.
    static func exactBlock(
        trigger: String,
        transform: @escaping @Sendable (inout EditorState, _ from: Position, _ to: Position) throws -> Void
    ) -> InputRule {
        InputRule(
            find: { before in
                before == trigger
                    ? InputRuleMatch(range: 0..<trigger.count, text: trigger)
                    : nil
            },
            transform: { state, match, blockTextStart in
                try transform(
                    &state,
                    blockTextStart + match.range.lowerBound,
                    blockTextStart + match.range.upperBound
                )
            }
        )
    }
}

/// The literal document/selection captured just before an Input Rule fired, so
/// Backspace immediately after a shortcut can restore the typed Markdown. The
/// ProseKit analogue of Tiptap's input-rule plugin undo state.
public struct AppliedInputRule: Sendable, Equatable {
    public var beforeDocument: Document
    public var beforeSelection: TextSelection
}

public enum InputRules {
    /// The StarterKit rules available today: block shortcuts first, then the
    /// inline mark shortcuts. List / codeBlock / task rules join as those node
    /// types land (slices 12, 14, 15).
    public static let starterKit: [InputRule] =
        headingRules + [blockquoteRule] + bulletListRules + [orderedListRule] + markRules

    /// Inline mark shortcuts. Bold (`**`/`__`) precede italic (`*`/`_`) so a
    /// double-delimiter run resolves to bold, not nested italic. Code rejects a
    /// preceding backtick; code/bold/italic exclusions still come from MarkRules.
    static let markRules: [InputRule] = [
        .mark(delimiter: "**", mark: .bold),
        .mark(delimiter: "__", mark: .bold),
        .mark(delimiter: "~~", mark: .strike),
        // Reject an opening delimiter preceded by the same character so a
        // malformed `**Bold*` / `__Bold_` tail stays literal instead of
        // italicising from the second delimiter (Tiptap parity).
        .mark(delimiter: "*", mark: .italic, rejectOpeningPrecededBy: "*"),
        .mark(delimiter: "_", mark: .italic, rejectOpeningPrecededBy: "_"),
        .mark(delimiter: "`", mark: .code, rejectWhitespaceOnlyContent: false, rejectOpeningPrecededBy: "`"),
    ]

    /// `> ` at a paragraph's start wraps it in a blockquote.
    static let blockquoteRule = InputRule.exactBlock(trigger: "> ") { state, from, to in
        guard let info = state.document.blockInfo(containing: from) else { return }
        // After dropping the trigger the block shrinks by its length; wrap the
        // shortened block. The caret lands one Position deeper (past the new
        // blockquote's opening token).
        let shortened = info.start..<(info.start + info.node.nodeSize - (to - from))
        try state.dispatch(Transaction(
            steps: [
                ReplaceStep(from: from, to: to, insertText: ""),
                WrapInStep(blockRange: shortened, containerType: "blockquote"),
            ],
            selection: TextSelection(anchor: from + 1, head: from + 1),
            origin: .local
        ))
    }

    /// `- ` / `* ` at a paragraph's start wraps it in a one-item bullet list.
    static let bulletListRules: [InputRule] = ["- ", "* "].map { trigger in
        InputRule.exactBlock(trigger: trigger) { state, from, to in
            guard let info = state.document.blockInfo(containing: from) else { return }
            let shortened = info.start..<(info.start + info.node.nodeSize - (to - from))
            try state.dispatch(Transaction(
                steps: [
                    ReplaceStep(from: from, to: to, insertText: ""),
                    WrapInListStep(blockRange: shortened, listType: "bulletList"),
                ],
                selection: TextSelection(anchor: from + 2, head: from + 2),
                origin: .local
            ))
        }
    }

    /// `1. ` at a paragraph's start wraps it in a one-item ordered list.
    static let orderedListRule = InputRule.exactBlock(trigger: "1. ") { state, from, to in
        guard let info = state.document.blockInfo(containing: from) else { return }
        let shortened = info.start..<(info.start + info.node.nodeSize - (to - from))
        try state.dispatch(Transaction(
            steps: [
                ReplaceStep(from: from, to: to, insertText: ""),
                WrapInListStep(blockRange: shortened, listType: "orderedList", listAttrs: ["start": .int(1)]),
            ],
            selection: TextSelection(anchor: from + 2, head: from + 2),
            origin: .local
        ))
    }

    /// `#`…`######` + space → heading of that level (Q5).
    static let headingRules: [InputRule] = (1...6).map { level in
        InputRule.exactBlock(trigger: String(repeating: "#", count: level) + " ") { state, from, to in
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

    /// Fires the first rule whose finder matches the collapsed caret's block
    /// text. Returns whether a rule transformed the document.
    @discardableResult
    public static func apply(_ rules: [InputRule], to state: inout EditorState) throws -> Bool {
        guard state.selection.isCollapsed,
              let blockTextStart = state.document.blockTextStart(at: state.selection.head) else {
            return false
        }
        let head = state.selection.head
        let before = (try? state.document.text(from: blockTextStart, to: head)) ?? ""
        for rule in rules {
            if let match = rule.find(before) {
                // Snapshot the literal pre-rule document so Backspace can revert
                // the shortcut. Captured before the transform; recorded after,
                // since the transform's own dispatch clears the slot.
                let beforeDocument = state.document
                let beforeSelection = state.selection
                try rule.transform(&state, match, blockTextStart)
                state.recordAppliedInputRule(beforeDocument: beforeDocument, beforeSelection: beforeSelection)
                return true
            }
        }
        return false
    }
}
