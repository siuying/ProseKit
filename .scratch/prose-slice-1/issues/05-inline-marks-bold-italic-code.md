# 05 — Inline marks: bold / italic / code

Status: done

## What to build

Inline formatting over text. A user selects a range and toggles a mark, or sets a
mark at a collapsed caret so the next typed text inherits it.

`ProseModel`: `AddMarkStep` / `RemoveMarkStep` (apply + invert), and the
typing-mark state at a collapsed caret (the set of marks the next inserted text
will carry). `toggleMark` `Command`s decide add-vs-remove based on whether the
whole selection already has the mark.

`ProseEditor`: mark Render Hooks map each mark to CoreText attributes —
`bold`/`italic` adjust the font traits, `code` switches to a monospace font (and
any code styling). Toggling is wired to a keymap (`⌘B`, `⌘I`) and a debug control
for `code`. Re-typesetting affected Boxes reflects the new attributes.

This is the first slice where a single text run carries overlapping marks
(bold+italic), so mark *sets* (not a single style) must render correctly.

## Acceptance criteria

- [ ] Selecting a range and pressing ⌘B toggles bold on/off over exactly that range (Add/RemoveMarkStep), reflected in rendering
- [ ] ⌘I toggles italic; bold+italic on the same span renders bold-italic
- [ ] The `code` mark renders in a monospace font
- [ ] At a collapsed caret, toggling a mark sets a typing-mark; subsequently typed text carries that mark; moving the caret clears it
- [ ] `AddMarkStep`/`RemoveMarkStep` apply and invert (round-trip unit-tested)
- [ ] `toggleMark` removes the mark when the whole selection already has it, otherwise adds it (unit-tested)

## Blocked by

- 02 — Type into a paragraph

## Comments

2026-06-10: User testing found ⌘B/⌘I inert in the example app. The keymap
exists (`ProseView.keyCommands`) but UIKit routes ⌘B/⌘I on a UITextInput first
responder to the standard `toggleBoldface(_:)`/`toggleItalics(_:)` actions,
which ProseView doesn't implement; and with selection broken (see 03 comment /
issue 10) a collapsed-caret toggle only sets an invisible typing mark.
Follow-up filed as 09 (hardware keyboard: caret movement & reliable ⌘B/⌘I).
