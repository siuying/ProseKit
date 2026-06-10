# 09 — Hardware keyboard: caret movement & reliable ⌘B/⌘I

Status: ready-for-agent

## Problem

Reported testing the example app after 05 landed: arrow keys do not move the
caret, and ⌘B does not bold.

Two distinct root causes in `Sources/ProseEditor/ProseView.swift`:

1. **No arrow-key handling exists.** A custom `UITextInput` view gets
   `insertText`/`deleteBackward` from the system keyboard plumbing, but caret
   navigation is the view's job — there is no `pressesBegan` override and no
   arrow-key entries in `keyCommands`, so arrow keys are silently dropped.
2. **⌘B/⌘I are wired only as custom `UIKeyCommand`s** (`ProseView.keyCommands`).
   For a first responder conforming to `UITextInput`, UIKit routes ⌘B/⌘I to the
   standard `UIResponderStandardEditActions` selectors `toggleBoldface(_:)` /
   `toggleItalics(_:)` — which `ProseView` does not implement — and the custom
   key commands don't set `wantsPriorityOverSystemBehavior`. Even when the
   toggle does run, a collapsed caret only sets an invisible typing mark, so
   with selection broken (see 10) there is nothing to observe.

## What to build

`ProseEditor`:

- `pressesBegan(_:with:)` (or arrow `UIKeyCommand`s) mapping ←/→ to head ±1
  (clamped to valid Positions), ↑/↓ to the Position nearest the caret rect's x
  in the line fragment above/below (via `GeometryMapper`), crossing block
  boundaries.
- Shift + arrows extends a `TextSelection` (anchor fixed, head moves); plain
  arrows collapse an existing selection to its edge before moving.
- Implement `toggleBoldface(_:)` / `toggleItalics(_:)` standard edit actions,
  delegating to the existing `Commands.toggleMark` path; keep the keymap
  entries and set `wantsPriorityOverSystemBehavior` where appropriate so ⌘B/⌘I
  reach us regardless of which route UIKit picks.

## Acceptance criteria

- [ ] ←/→ moves the caret one Position, clamped at document edges, crossing block boundaries
- [ ] ↑/↓ moves the caret to the nearest Position on the adjacent line fragment, including across blocks
- [ ] Shift+arrows extends/shrinks the selection; plain arrow collapses a selection to the corresponding edge
- [ ] ⌘B with a range selected visibly toggles bold; ⌘I italics (manually verified in the example app with a hardware keyboard)
- [ ] Caret-movement logic (Position arithmetic + up/down targeting) is unit-tested off-screen

## Blocked by

- 03 — Caret placement & range selection
- 05 — Inline marks: bold / italic / code
