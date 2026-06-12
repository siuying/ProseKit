# 16 — Hardware keyboard shortcuts (+ Tab/Shift+Tab sink/lift)

Status: ready-for-agent

## What to build

Hardware-keyboard affordances (Q5), all driving existing Commands:

- ⌘B / ⌘I / ⌘U (bold/italic/underline), ⌘⇧S strike, ⌘E inline code,
  ⌘⌥1–4 headings.
- Tab / Shift+Tab sink / lift a list item (needs lists, slice 14).
- ⌘Z / ⌘⇧Z undo / redo (history slice).

### Critical CoreText/UIKit note (from prose-slice-1/05 + 09)
⌘B / ⌘I must be handled via the standard responder actions
`toggleBoldface(_:)` / `toggleItalics(_:)`, **not** `keyCommands` — UIKit routes
those first on a UITextInput first responder. ⌘U similarly maps to
`toggleUnderline(_:)`. The remaining shortcuts go through `keyCommands`.

## Acceptance criteria

- [ ] ⌘B/⌘I/⌘U toggle via the responder actions and reflect/return correct state
- [ ] ⌘⇧S, ⌘E, ⌘⌥1–4 toggle strike / code / headings via keyCommands
- [ ] Tab / Shift+Tab sink/lift a list item (needs 14)
- [ ] ⌘Z / ⌘⇧Z route into the Step-based history (not NSUndoManager directly)

## Blocked by

- 14 — Lists (for Tab/Shift+Tab). Mark/heading shortcuts only need 01/06.

## Comments

2026-06-12: ready-for-agent. Hardware-keyboard behaviour can only be *verified*
on a device/simulator with a keyboard; wire the actions to the (tested) Commands
and verify in the app. Heed the responder-action vs keyCommands gotcha — it has
already bitten this project once (issue prose-slice-1/05 comment).
