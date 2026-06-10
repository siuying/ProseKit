# 13 — System selection UX via UITextInteraction

Status: ready-for-human

## What to build

Make selection look and feel like a regular iOS editor — magnifier loupe,
selection handles, system caret, double-tap word select, edit menu — by
attaching `UITextInteraction(for: .editable)` to `ProseView` and letting the
system own all selection chrome. `ProseView`'s job narrows to answering
geometry truthfully (decided 2026-06-10; alternative of hand-built chrome
rejected).

### Adopt the interaction, delete the scaffolding

- Attach `UITextInteraction(for: .editable)` in `ProseView` init.
- Delete the custom chrome it replaces: `caretTimer`/`showsCaret`/
  `startCaretBlink`, `drawCaretIfNeeded`, `drawSelectionIfNeeded`, and the
  `touchesBegan`/`touchesMoved` overrides (they fight the interaction's
  gesture recognizers — double carets, broken drags).
- System caret color comes from `tintColor`.
- Keep the `pressesBegan` hardware arrow-key handling from issue 09; drop its
  now-dead `showsCaret = true` lines.

### Geometry the system needs

- `selectionRects(for:)` currently returns `[]` — highlight and handles would
  be invisible. Return a `UITextSelectionRect` subclass (rect, writing
  direction, `containsStart`/`containsEnd`) built from
  `GeometryMapper.selectionRects`, one per Line Fragment, with
  `containsStart`/`containsEnd` on the first/last so the handles know where
  to sit.
- `firstRect(for:)` currently returns the start caret rect; return the real
  first-line rect of the range (loupe/menu positioning uses it).
- `position(from:in:direction:offset:)` ignores its direction (treats up/down
  as character offsets) — route through `GeometryMapper`'s above/below.
  `UITextInputStringTokenizer` (double-tap word select, line granularity)
  depends on this being honest.
- Call `inputDelegate?.selectionWillChange/selectionDidChange` around
  selection mutations (`selectedTextRange` setter) — the interaction listens.

### Edit menu (plain-text fidelity)

`UITextInteraction` surfaces the edit menu; its items route through the
standard responder actions, none of which exist yet.

- Implement `canPerformAction(_:withSender:)` plus `cut:`, `copy:`, `paste:`,
  `select:`, `selectAll:` using the existing `text(in:)` /
  `replace(_:withText:)` plumbing and `UIPasteboard.general` strings.
- Pasted text containing newlines splits blocks (each `\n` behaves like
  typing Return), consistent with `insertText`.
- Rich, Mark/structure-preserving copy/paste is out of scope — issue 12
  (Slice) covers it.

### Out of scope

- Scrolling, autoscroll-during-drag, keyboard avoidance — issue 14.
- Rich pasteboard fidelity — issue 12.
- Marked-text/IME interplay — issue 08.
- Caret/handle restyling (`UITextSelectionDisplayInteraction`) — not needed.

## Acceptance criteria

- [ ] Press-and-drag shows the system magnifier loupe and moves the caret under it *(machinery in place — needs hands-on gesture check)*
- [x] A range selection shows system handles; dragging a handle updates the selection, highlight staying under the glyphs across wrap and block boundaries *(highlight + handles verified visually in simulator; handle drag needs hands-on check)*
- [x] Exactly one caret, system-drawn, blinking; no custom caret remains
- [x] Double-tap selects the word under the finger *(tokenizer word selection covered by tests; gesture itself needs hands-on check)*
- [x] Edit menu appears on selection/long-press; Copy/Cut/Paste/Select All work with plain text *(actions covered by tests; menu appearance needs hands-on check)*
- [x] Pasting multi-line plain text produces multiple blocks
- [x] Hardware arrow keys (with/without ⇧) still move/extend the selection (issue 09 regression check) *(geometry covered by tests; `pressesBegan` path unchanged)*

## Blocked by

- 03 — Caret placement & range selection (done)
- 09 — Hardware keyboard caret movement (done)
- 10 — CoreText geometry must match rendering (done)

## Comments

**2026-06-10 (agent)** — Implemented on branch `prose-slice-1-13-uitextinteraction`, TDD
(12 new `ProseViewTests` on the iOS simulator; 40 tests green on sim, 28 on macOS).

- `UITextInteraction(for: .editable)` attached in init; deleted `caretTimer`/
  `showsCaret`/`startCaretBlink`, `drawCaretIfNeeded`, `drawSelectionIfNeeded`,
  and the `touchesBegan`/`touchesMoved` overrides.
- `selectionRects(for:)` returns `ProseTextSelectionRect` per Line Fragment with
  `containsStart`/`containsEnd`; `firstRect(for:)` returns the real first-line
  rect; `position(from:in:direction:offset:)` routes up/down through
  `GeometryMapper`; `selectedTextRange` setter fires
  `selectionWillChange`/`selectionDidChange`.
- Edit menu: `canPerformAction` + `cut:`/`copy:`/`paste:`/`select:`/`selectAll:`.
  `insertText` now treats every embedded `\n` as Return, so multi-line paste
  splits blocks. `text(in:)` stitches cross-block ranges with `\n` (Select All →
  Copy, and `UITextInputStringTokenizer` context queries, were returning nil).
- Two findings beyond the issue text:
  - `UIPasteboard.general` is unauthorized in unhosted test bundles, so
    `ProseView.pasteboard` is injectable (defaults to `.general`).
  - `UITextInteraction` only activates its `UITextSelectionDisplayInteraction`
    from its own tap gestures; on programmatic `becomeFirstResponder` no caret
    appeared. `ProseView` now toggles `isActivated` on responder transitions,
    matching UITextView. Verified visually: blinking system caret and
    handles/highlight render in the example app.
- Example app now focuses the editor on launch.
- Remaining hands-on checks (can't synthesize touches from CLI): loupe during
  drag, handle dragging, double-tap gesture, edit menu appearance.
