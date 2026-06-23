# Implementation plan: Markdown input rules

Bring Tiptap-style Markdown shortcuts to ProseKit's native editor. The target is
ProseKit's domain term **Input Rule**: a pattern watched at the caret during typing
that rewrites just-typed text into structure or formatting, with immediate
Backspace reverting the rule.

## Source documents

- Glossary — [CONTEXT.md](../../CONTEXT.md), especially **Input Rule**, **Mark**,
  **Step**, **Transaction**, **Mapping**, and **Extension**.
- Existing engine — [`Sources/ProseEditor/InputRule.swift`](../../Sources/ProseEditor/InputRule.swift)
- Existing tests — [`Tests/ProseEditorTests/InputRuleTests.swift`](../../Tests/ProseEditorTests/InputRuleTests.swift)
- Tiptap reference checkout — `/Users/siuying/Developer/personal/tiptap`
- Research summary — `/Users/siuying/Developer/personal/mnemo/docs/research/2026-06-22-tiptap-markdown-shortcuts.md`
- Key Tiptap files:
  - `packages/core/src/InputRule.ts`
  - `packages/core/src/inputRules/markInputRule.ts`
  - `packages/extension-italic/src/italic.ts`
  - `packages/extension-bold/src/bold.tsx`
  - `packages/extension-code/src/code.ts`
  - `packages/core/src/commands/undoInputRule.ts`

## Architecture recap (what exists today)

- `InputRule` is an exact string trigger plus a transform closure.
- `InputRules.starterKit` currently contains block-start rules:
  - `# ` … `###### ` → heading levels 1–6
  - `> ` → blockquote
  - `- ` / `* ` → bullet list
  - `1. ` → ordered list
- `InputRules.apply(_:to:)` is headless and unit-tested directly. It checks the
  text from the current block's text start to the collapsed caret and fires only
  when that whole text equals a trigger.
- The live typing paths (`ProseView`, `MacProseView`, `EditorCore.insertText`) do
  not currently run input rules after typed text.
- The current source comment explicitly leaves live wiring and Backspace revert for
  a later slice.

## Target behavior

### Inline mark shortcuts

- `*text*` → italic `text`
- `_text_` → italic `text`
- `**text**` → bold `text`
- `__text__` → bold `text`
- `` `text` `` → code `text`
- `~~text~~` → strike `text`

### Existing block shortcuts

Preserve the existing block rule behavior, then run it from the live typing path:

- `# ` … `###### ` → heading
- `> ` → blockquote
- `- ` / `* ` → bullet list
- `1. ` → ordered list

### Undo shortcut

Backspace immediately after an input rule restores the literal text the user typed,
matching Tiptap's `undoInputRule()` behavior.

## Design shape

### Generalize the rule model

Replace the current exact-trigger-only shape with a finder-based shape while keeping
exact triggers as a convenience constructor.

Sketch:

```swift
public struct InputRuleMatch: Sendable, Equatable {
    /// Range in the current block text, measured in the same character units used
    /// by Document text positions.
    public var range: Range<Int>

    /// Optional inner content range for mark rules. For `*abc*`, this points to
    /// `abc` within `range`.
    public var contentRange: Range<Int>?

    /// Original text matched by the finder, useful for undo metadata.
    public var text: String

    /// Extra data for rules such as heading level or code language later.
    public var data: [String: JSONValue]
}

public struct InputRule: Sendable {
    public let find: @Sendable (_ textBeforeCaret: String) -> InputRuleMatch?
    let transform: @Sendable (inout EditorState, InputRuleMatch, _ blockTextStart: Position) throws -> Void
}
```

Exact block triggers become `InputRule.exact(trigger:)`, implemented by a finder
that returns a match only when `textBeforeCaret == trigger`.

Inline mark rules use suffix finders: they scan the text before the caret and
return the final matched span, not any preceding whitespace. This mirrors Tiptap's
function-based finder for inline code, which avoids consuming text before the
shortcut.

### Add helper builders

Add helper constructors alongside the current rule definitions:

- `InputRule.exactBlock(trigger:transform:)`
- `InputRule.mark(find:mark:)`
- `InputRule.mark(delimiter:mark:)` for symmetric delimiters such as `*`, `**`,
  `_`, `__`, `` ` ``, and `~~`

A mark rule transforms the matched range in one local Transaction:

1. Delete the closing delimiter.
2. Delete the opening delimiter.
3. Add the Mark over the shifted content range.
4. Place the Selection after the marked content.

For `*abc*` at block text position `s`:

- Original: `s..<s+5`
- Delete closing delimiter: `s+4..<s+5`
- Delete opening delimiter: `s..<s+1`
- Apply italic to shifted content: `s..<s+3`
- Selection: `s+3`

This keeps the existing text node content and uses `AddMarkStep`, so existing Mark
coexistence rules continue to flow through `MarkRules.adding(...)`.

### Store immediate undo metadata

Add a small editor-state/core field for the most recently applied input rule. It is
ProseKit's equivalent of Tiptap's input-rule plugin state.

Sketch:

```swift
public struct AppliedInputRule: Sendable, Equatable {
    public var inverseSteps: [any Step]
    public var restoredText: String
    public var restoredSelection: TextSelection
}
```

The implementation can store the literal typed text plus either inverse Steps or a
ready-to-dispatch Transaction. The observable behavior is that `undoInputRule()`
runs before ordinary Backspace handling and restores the literal Markdown shortcut.

Clear this metadata when:

- selection changes,
- a non-input-rule Transaction applies,
- another edit occurs,
- undo/redo applies,
- remote collaboration changes apply.

### Wire live typing

Run input rules after successful plain text insertion from both editor shells.

- `EditorCore.insertText(_:)` remains the single public typing seam.
- Add an input-rule pass after `state.insertText(text)` when the inserted text is
  user text and the selection is collapsed.
- On iOS and macOS, marked-text / IME composition should not apply rules mid-
  composition. Run after committed input, mirroring Tiptap's composition-end path.
- Newline keeps using `Commands.splitBlock()` first; rules that need Enter-triggered
  behavior can be added in a later phase.

## Phase 0 — Preserve current block engine behind finder API

Goal: the `InputRule` type can express both exact triggers and suffix/capture
matches, with no visible behavior change.

1. Introduce `InputRuleMatch` and finder-based `InputRule`.
2. Add an exact-trigger convenience initializer.
3. Port existing heading, blockquote, bullet-list, and ordered-list rules to the new
   shape.
4. Keep `InputRules.apply(InputRules.starterKit, to: &state)` as the public headless
   entry point.
5. Update `InputRuleTests` only as needed for the new internals; existing assertions
   should continue to pass.

Acceptance:

- All current `InputRuleTests` pass unchanged in behavior.
- New matcher unit tests cover exact trigger matches and non-matches.

## Phase 1 — Add live block input rules

Goal: existing block shortcuts fire while typing in both editor shells.

1. Add `EditorCore.applyInputRules(_:)` or fold the call into `EditorCore.insertText`.
2. Call `InputRules.apply(InputRules.starterKit, to: &state)` after text insertion
   when input rules are enabled.
3. Add an option on `EditorCore` to enable/disable input rules, defaulting to enabled
   to match Tiptap.
4. Ensure relayout/notification sees both the inserted text and the follow-up rule
   transform.
5. Add iOS and macOS view tests for typing `# ` and `> ` into an empty paragraph.

Acceptance:

- Typing `# ` turns the current paragraph into a level-1 heading.
- Typing `> ` wraps the current paragraph in a blockquote.
- Direct headless tests and live view tests both pass.

## Phase 2 — Inline mark matchers and headless transforms

Goal: inline shortcut behavior works headlessly before it is exposed through live
view tests.

1. Add suffix finder helpers for symmetric delimiters.
2. Port Tiptap's delimiter rules into Swift matchers:
   - `*text*` and `_text_` reject empty/whitespace-only content.
   - `**text**` and `__text__` reject empty/whitespace-only content.
   - `` `text` `` rejects empty content and a preceding backtick.
   - `~~text~~` rejects empty/whitespace-only content.
3. Add `InputRule.mark(...)` helper that applies delimiter deletion plus
   `AddMarkStep`.
4. Add inline rules to `InputRules.starterKit` after the existing block rules.
5. Keep block `* ` as a bullet-list exact trigger; `*text*` is a separate suffix
   match and should not interfere.

Acceptance:

- Headless tests verify:
  - `*Italic*` becomes an italic-marked `Italic` text run.
  - `_Italic_` becomes italic.
  - `**Bold**` and `__Bold__` become bold.
  - `` `Code` `` becomes code.
  - `~~Strike~~` becomes strike.
  - delimiter-only and whitespace-only forms do not fire.
  - a preceding normal character before code is preserved: `a`Code`` → `aCode`
    with only `Code` marked.

## Phase 3 — Live inline mark rules

Goal: typing Markdown inline shortcuts in the editor produces formatted text.

1. Exercise inline rules through `EditorCore.insertText` after Phase 2 is headless.
2. Add `ProseViewTests` and `MacProseViewTests` for live insertion:
   - `*Italic* ` produces an italic run and leaves the trailing space plain.
   - `**Bold**` produces a bold run.
   - `` `Code` `` produces a code run.
   - `a`Code`` preserves the preceding `a` as plain text.
3. Verify the active typing Mark does not stay enabled after the shortcut; subsequent
   typed characters are plain unless a toolbar/key command explicitly set a typing
   mark.
4. Verify mark exclusions still come from `MarkRules`; for example, code excludes
   bold/italic according to existing Mark rules.

Acceptance:

- Live typing produces the same document shape as the headless tests.
- Characters typed after the shortcut are not accidentally marked by the shortcut.

## Phase 4 — Immediate Backspace revert

Goal: Backspace immediately after a shortcut restores literal Markdown text.

1. Record applied input-rule metadata when a rule transform succeeds.
2. Add `Commands.undoInputRule()` or an `EditorCore.undoInputRule()` method.
3. In iOS `ProseView.deleteBackward()` and macOS `MacProseView.deleteBackwardFromInput()`,
   try input-rule undo before structural Backspace commands (`joinBackward`,
   `liftOutOfContainer`) and before plain character deletion.
4. Clear the pending rule metadata on selection movement and unrelated transactions.
5. Add tests for block and inline cases:
   - Type `# `, press Backspace → literal `# ` in a paragraph.
   - Type `*Italic*`, press Backspace → literal `*Italic*`.
   - Move the selection, press Backspace → normal Backspace behavior, not input-rule
     undo.

Acceptance:

- Backspace immediately after any applied input rule restores the typed Markdown.
- A later Backspace after unrelated edits behaves normally.

## Phase 5 — Composition, replacement ranges, and paste boundaries

Goal: live rules behave correctly with platform text input details.

1. Ensure iOS marked text and macOS marked text do not trigger rules until committed.
2. Ensure macOS replacement ranges select and replace text before rule evaluation.
3. Keep paste separate from input rules. Tiptap has paste rules as a sibling system;
   this plan only covers typing-time Input Rules.
4. Add tests for replacement input where existing text is replaced by a shortcut.
5. Add at least one IME/marked-text regression test if the current test harness can
   express it.

Acceptance:

- Shortcuts trigger only after committed text input.
- Replacement-range typing can still trigger a shortcut after the replacement is in
  the Document.
- Plain paste does not unexpectedly run typing-time input rules.

## Phase 6 — Documentation and extension seam preparation

Goal: the implementation is documented in current architecture terms and remains
ready for the future Extension API.

1. Update `CONTEXT.md` only if the glossary needs sharper wording after the work.
2. Document the built-in StarterKit input rules in the public README/API docs.
3. Keep rule construction isolated enough that a future Extension type can contribute
   rules the way Tiptap extensions do via `addInputRules()`.
4. Add a short source comment mapping ProseKit helpers to the Tiptap concepts:
   `markInputRule`, textblock conversion, wrapping, and immediate undo.

Acceptance:

- Public docs list the supported shortcuts.
- Built-in rules are grouped so future Extension contributions can be appended in
  order.

## Testing strategy

### Headless unit tests

- Matcher tests for each delimiter and edge case.
- Transform tests for each supported shortcut.
- Existing block tests retained.
- Mark-exclusion tests for code/bold/italic interactions.
- Backspace revert tests at `EditorCore` or `EditorState` level.

### View integration tests

- iOS `ProseView` typing tests for block and inline shortcuts.
- macOS `MacProseView` typing tests for block and inline shortcuts.
- Backspace-revert tests in both shells.

### Regression coverage copied from Tiptap behavior

- Preceding character is not consumed for inline code.
- Empty or whitespace-only delimiter pairs do not transform.
- Only the final suffix before the caret transforms when multiple pairs exist.
- Subsequent typing after a mark shortcut is plain text.

## Risks and open items

- `AddMarkStep` currently requires the mark range to stay inside one text node. The
  first implementation should keep inline matches inside one text node and add tests
  around split runs.
- Swift regex/finder code must measure match ranges in the same character units as
  `Position` math. Prefer integer offsets derived from `String.count` over UTF-16
  offsets.
- Undo metadata shape needs to fit existing history coalescing. The observable
  behavior is immediate Backspace revert; ordinary undo history should still record
  user edits as local Transactions.
- Extension-contributed input rules are a future seam. This plan keeps the current
  direct `starterKit` model but shapes the code so that future Extensions can append
  rules in order.

## Not in scope

- Paste rules for Markdown content.
- Full Markdown document parsing/serialization.
- Link shortcuts such as `[label](url)`.
- Code block shortcuts with language capture.
- A general plugin system.
