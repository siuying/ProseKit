# Implementation plan: mentions and hashtags

Add typing-time entity features such as `@user` and `#hashtag` to ProseKit. This
plan treats mentions/hashtags as a higher-level feature built on the same editing
seams as Input Rules, but with an interactive suggestion session before the final
Document rewrite.

## Source documents

- Glossary — [CONTEXT.md](../../CONTEXT.md), especially **Document**, **Mark**,
  **Position**, **Step**, **Transaction**, **Selection**, **Extension**, **Render
  Hook**, and **Input Rule**.
- Existing model:
  - [`Sources/ProseModel/Mark.swift`](../../Sources/ProseModel/Mark.swift)
  - [`Sources/ProseModel/Schema.swift`](../../Sources/ProseModel/Schema.swift)
  - [`Sources/ProseModel/Step.swift`](../../Sources/ProseModel/Step.swift)
- Existing editor seams:
  - [`Sources/ProseEditor/EditorCore.swift`](../../Sources/ProseEditor/EditorCore.swift)
  - [`Sources/ProseEditor/EditorState.swift`](../../Sources/ProseEditor/EditorState.swift)
  - [`Sources/ProseEditor/Commands.swift`](../../Sources/ProseEditor/Commands.swift)
  - [`Sources/ProseEditor/ProseView.swift`](../../Sources/ProseEditor/ProseView.swift)
  - [`Sources/ProseEditor/MacProseView.swift`](../../Sources/ProseEditor/MacProseView.swift)
- Rendering patterns:
  - [`Sources/ProseEditor/BlockStyle.swift`](../../Sources/ProseEditor/BlockStyle.swift)
  - [`Sources/ProseEditor/Marks/Link.swift`](../../Sources/ProseEditor/Marks/Link.swift)
  - [`Sources/ProseEditor/Marks/Highlight.swift`](../../Sources/ProseEditor/Marks/Highlight.swift)
- Related plan — [Markdown input rules](./markdown-input-rules.md)

## Architecture recap (what exists today)

- ProseKit's inline content is text-only today; `Node` supports text runs carrying
  `Mark`s.
- `Mark` already stores a type plus typed attrs.
- `Schema.slice1` currently knows marks such as bold, italic, code, strike,
  highlight, and link.
- Commands already apply marks via `AddMarkStep` / `RemoveMarkStep` and replace text
  via `ReplaceStep` in Transactions.
- Rendering already maps marks to CoreText attributes through mark render units and
  `BlockStyle`.
- There is not yet a general Extension API or general plugin runtime; built-ins are
  wired directly.

## Product shape

### Mentions

Typing `@` followed by a query opens a suggestions menu. Selecting a user replaces
that query range with display text and marks it as a mention.

Example document result:

```swift
.text("Jane Appleseed", marks: [
    Mark(type: "mention", attrs: [
        "id": .string("user-123"),
        "label": .string("Jane Appleseed")
    ])
])
```

### Hashtags

Typing `#` followed by a tag query opens a suggestions menu or allows free-form tag
commit. Selecting or committing a tag replaces the query range with display text and
marks it as a hashtag.

Example document result:

```swift
.text("#swift", marks: [
    Mark(type: "hashtag", attrs: [
        "tag": .string("swift")
    ])
])
```

## Design decisions for v1

- Model mentions and hashtags as **Marks**, not inline atom Nodes. The current inline
  model is text-only, and marks already support attrs and collaboration encoding.
- Store stable identity in mark attrs:
  - Mention: `id`, `label`, optional `avatarURL` / `url` if the host wants it.
  - Hashtag: `tag`, optional `label` if display differs from canonical value.
- The rendered visible text remains normal text. The Mark carries the entity meaning.
- A selected suggestion commits through a normal local Transaction so history,
  selection, layout, and collaboration observe it through existing seams.
- Autocomplete UI is editor chrome anchored to caret geometry, not content in the
  Document.

## Phase 0 — Domain and model contract

Goal: define the persisted representation without UI.

1. Add mention/hashtag mark factories:

   ```swift
   extension Mark {
       public static func mention(id: String, label: String) -> Mark
       public static func hashtag(_ tag: String) -> Mark
   }
   ```

2. Add `mention` and `hashtag` to `Schema.slice1.marks`.
3. Add schema/json tests proving mention and hashtag marks round-trip through
   Tiptap-style JSON.
4. Add Yjs mark-attribute tests proving the plain-name mark path handles:
   - `mention → { mention: { id, label } }`
   - `hashtag → { hashtag: { tag } }`

Acceptance:

- Documents containing mention/hashtag marks validate.
- JSON encode/decode preserves mark attrs.
- Yjs mark attribute conversion preserves mark attrs.

## Phase 1 — Entity commit commands

Goal: programmatic commands can replace typed query text with entity text and apply
an entity Mark.

1. Add command APIs:

   ```swift
   Commands.setMention(id: String, label: String, replacing range: Range<Position>)
   Commands.setHashtag(tag: String, replacing range: Range<Position>)
   Commands.removeEntityMark(type: String)
   ```

2. Implement commit as one Transaction:
   - `ReplaceStep(from: range.lowerBound, to: range.upperBound, insertText: displayText)`
   - `AddMarkStep(from: range.lowerBound, to: range.lowerBound + displayText.count, mark: entityMark)`
   - Selection collapsed after the inserted display text.
3. Keep entity insertion inside one text block for v1, matching current mark-step
   limits.
4. Add tests for replacing:
   - `@ja` with `Jane Appleseed` carrying a mention Mark.
   - `#swi` with `#swift` carrying a hashtag Mark.
   - a non-collapsed selection with an entity.

Acceptance:

- Commands produce expected text runs and marks.
- Selection lands after the inserted entity text.
- Undo/redo treats the entity commit as one local user action.

## Phase 2 — Trigger/session detection engine

Goal: the editor can identify an active mention or hashtag query at the caret.

1. Add a headless `EntityTriggerSession` type:

   ```swift
   public struct EntityTriggerSession: Equatable, Sendable {
       public enum Kind: Sendable { case mention, hashtag }
       public var kind: Kind
       public var trigger: Character
       public var query: String
       public var range: Range<Position>
   }
   ```

2. Add a detector that reads the current block text before the collapsed caret and
   returns a session when the suffix matches a trigger.
3. Mention rules:
   - Trigger: `@`
   - Query characters: letters, numbers, underscore, hyphen, dot as needed by host
     policy.
   - Boundary required before `@`: start of block or whitespace/punctuation.
   - Do not match email addresses like `a@b.com`.
4. Hashtag rules:
   - Trigger: `#`
   - Query characters: letters, numbers, underscore, hyphen.
   - Boundary required before `#`: start of block or whitespace/punctuation.
   - Do not match inside URL fragments unless the host explicitly allows it.
5. End session when:
   - selection is not collapsed,
   - caret leaves the session range,
   - query contains a terminating character,
   - document changes remotely in a way that invalidates the range.

Acceptance:

- Unit tests cover start-of-block, after-space, punctuation boundary, no email
  match, no mid-word hashtag, and ending conditions.
- Detector reports `range` including the trigger and query, ready for replacement.

## Phase 3 — Suggestion provider seam

Goal: host apps can provide candidates without the editor knowing app data models.

1. Add candidate types:

   ```swift
   public struct MentionCandidate: Identifiable, Equatable, Sendable {
       public var id: String
       public var label: String
       public var subtitle: String?
       public var avatarURL: URL?
   }

   public struct HashtagCandidate: Identifiable, Equatable, Sendable {
       public var id: String { tag }
       public var tag: String
       public var count: Int?
   }
   ```

2. Add a provider protocol:

   ```swift
   @MainActor
   public protocol EntitySuggestionProvider: AnyObject {
       func mentionSuggestions(matching query: String) async -> [MentionCandidate]
       func hashtagSuggestions(matching query: String) async -> [HashtagCandidate]
       func canCreateHashtag(_ tag: String) -> Bool
   }
   ```

3. Add an `EditorCore` or view-level coordinator that:
   - observes text/selection changes,
   - starts/cancels async suggestion tasks,
   - debounces query changes,
   - exposes current session + candidates to UI.
4. Keep the provider optional. Without a provider, mention suggestions are empty;
   hashtags can still support free-form commit if enabled.

Acceptance:

- Tests with a fake provider verify cancellation, latest-query-wins behavior, and
  empty provider behavior.

## Phase 4 — Cross-platform suggestion UI

Goal: show and control an autocomplete menu on iOS and macOS.

1. Add an editor-owned suggestion overlay anchored to the caret rect from
   `geometryMapper`.
2. iOS:
   - Render a small SwiftUI/UIKit menu above the keyboard or near the caret.
   - Support tap selection.
   - Keep VoiceOver labels for candidate rows.
3. macOS:
   - Render an `NSPopover` or editor overlay near the caret.
   - Support mouse selection.
4. Common keyboard behavior:
   - Down/Up moves highlighted candidate.
   - Return/Tab commits highlighted candidate.
   - Escape dismisses.
   - Space or punctuation commits a free-form hashtag when allowed, otherwise
     dismisses.
5. Reposition overlay after layout, scroll, or selection changes.

Acceptance:

- UI tests can type `@ja`, see candidate rows, choose a candidate, and verify the
  Document contains the mention Mark.
- UI tests can type `#swi`, choose or commit `#swift`, and verify the hashtag Mark.
- Overlay follows caret while typing and disappears when the session ends.

## Phase 5 — Editing behavior around existing entities

Goal: entity-marked text behaves predictably after insertion.

1. Define deletion semantics for v1:
   - Backspace inside entity text edits normal text and preserves the Mark over the
     remaining text, or
   - Backspace at entity boundary deletes the whole entity.
2. Choose and encode that behavior in commands/tests. If whole-entity deletion is
   desired, add a command that detects entity marks around the caret and deletes the
   full marked range before plain `deleteBackward`.
3. Define cursor movement and selection behavior:
   - Text selection can still select inside entities in v1 if entities are Marks.
   - Later inline atom Nodes can make them indivisible.
4. Add tests for typing after an entity: subsequent text should not inherit the
   entity Mark.
5. Add tests for replacing an entity with plain text and removing entity marks.

Acceptance:

- Deletion and typing behavior around entity marks is documented in tests.
- Entity Marks do not accidentally extend to following typed text.

## Phase 6 — Rendering and interaction styling

Goal: entity marks are visible and interactive enough for v1.

1. Add mark render units for `mention` and `hashtag`.
2. Extend `RunStyle` / `BlockStyle` to provide a distinct entity tint or underline.
3. Add draw-time treatment similar to links if special overpainting is needed.
4. Add hit-testing affordance if the host needs taps/clicks:
   - `onMentionTap(id:)`
   - `onHashtagTap(tag:)`
5. Add rendering tests that verify attributed runs carry the expected entity
   attributes and visual snapshots differ from plain text where existing rendering
   tests use bitmap comparison.

Acceptance:

- Mention/hashtag runs render distinctly from plain text.
- Optional tap/click callbacks receive the entity attrs.

## Phase 7 — Collaboration and JSON interoperability

Goal: entity marks survive local/remote collaboration and export.

1. Add ProseKitYjs tests for mention and hashtag mark attributes.
2. Add JS interop fixture updates if the browser peer schema includes equivalent
   marks.
3. Preserve unknown mention attrs from richer peers, following ADR 0005/0006 style:
   known rendering may ignore unknown attrs, but the data remains in the Mark.
4. Ensure remote edits inside/around entity marked text map selection and suggestion
   sessions safely.

Acceptance:

- ProseKit ⇄ y-prosemirror round-trips mention/hashtag marks with attrs.
- Remote edits do not crash an active suggestion session; the session is dismissed
  or remapped according to the detector rules.

## Phase 8 — Future Extension API alignment

Goal: the implementation can move into Extension contributions later.

1. Keep mention and hashtag rules grouped as feature units:
   - schema marks,
   - render hooks,
   - commands,
   - trigger detectors,
   - suggestion provider hooks.
2. Shape the API so a future `MentionExtension` or `HashtagExtension` can contribute
   those pieces similarly to how Tiptap extensions contribute schema, commands,
   render hooks, and input rules.
3. Document the public host integration API in README/API docs.

Acceptance:

- Built-in mention/hashtag code has clear seams matching future Extension concepts.
- Host apps can enable mentions, hashtags, or both independently.

## Testing strategy

### Headless model tests

- Mark factories encode expected attrs.
- Schema validates mention/hashtag marks.
- Commands replace ranges and apply marks correctly.
- Undo/redo restores pre-commit text and selection.
- Entity text typed after commit does not inherit the entity Mark.

### Trigger/session tests

- `@` and `#` at block start.
- `@` and `#` after whitespace/punctuation.
- No mention in `a@b.com`.
- No hashtag mid-word unless allowed by policy.
- Unicode letters/numbers if supported by policy.
- Session dismissal on selection move and terminating punctuation.

### Provider/coordinator tests

- Debounce and cancellation.
- Latest query wins.
- Empty results.
- Free-form hashtag creation.

### View integration tests

- iOS suggestion overlay appears and commits a mention.
- macOS suggestion overlay appears and commits a mention.
- Keyboard navigation and Escape dismissal.
- Overlay tracks caret after scrolling/layout.

### Collaboration tests

- Yjs attribute round-trip for mention and hashtag marks.
- Browser peer interop when equivalent marks exist.

## Risks and open items

- **Mark vs inline atom**: Marks fit the current model. If product behavior later
  requires indivisible entities, inline atom Nodes will need a separate model slice.
- **Range math**: Detectors must convert Swift `String` ranges into ProseKit
  `Position`s using the same character-count assumptions as existing text Steps.
- **Async suggestions**: Provider results can arrive after the caret moved. The
  coordinator must bind each result to the session identity/query that requested it.
- **IME composition**: Trigger detection should run on committed text, not transient
  marked text.
- **Schema parity**: Browser Tiptap peers need matching mention/hashtag mark specs
  for full interop. Unknown mark preservation protects data, but rendering and
  behavior require known specs on both sides.

## Not in scope

- A full general Extension runtime.
- Inline atom Node support for indivisible mentions.
- Server-side user/tag search implementation.
- Rich mention cards, hover previews, permissions, or notification delivery.
- Automatic retroactive linking of all plain `@name` / `#tag` text outside the live
  suggestion flow.
