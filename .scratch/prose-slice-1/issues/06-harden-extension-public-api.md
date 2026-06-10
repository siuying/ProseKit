# 06 — Harden the Extension public API

Status: ready-for-human

## What to build

Consolidation + review checkpoint (HITL). By this point slices 01, 04, and 05
have introduced the slice-1 nodes, marks, commands, keymap entries, and Render
Hooks — possibly wired in ad hoc. This slice refactors all of them so they are
authored through a single Tiptap-style `Extension` bundle, and the editor is
configured by an ordered list of `Extension`s. Built-in features must use the same
API a third party would.

One `Extension` may contribute any of: Node/Mark specs (to the `Schema`),
`Command`s, keymap entries, and Render Hooks (`Mark → CoreText attributes`,
`Block Node → Layout Box`). The deliverable is the *public shape* of that API,
reviewed by a human before it ossifies, since later features and third parties
depend on it being right.

This is the moment to confirm: how Extensions are ordered/composed, how
conflicting contributions resolve, what a Render Hook's signature is, and how an
Extension reaches editor state in a Command.

## Acceptance criteria

- [ ] All slice-1 nodes (doc, paragraph, heading), marks (bold, italic, code), commands, and keymap entries are defined as `Extension`s — none wired directly into the engine
- [ ] The editor is constructed from an ordered `[Extension]`; reordering or removing one changes behavior predictably
- [ ] A Render Hook signature exists for both marks (→ CoreText attributes) and block nodes (→ Layout Box), exercised by the built-ins
- [ ] A short doc/example shows adding a trivial third-party mark (e.g. `underline`) end-to-end through the public API only, with no engine changes
- [ ] Human review sign-off on the public `Extension` API shape

## Blocked by

- 04 — Multi-block structural editing
- 05 — Inline marks: bold / italic / code
- 09 — Hardware keyboard: caret movement & reliable ⌘B/⌘I
- 10 — Geometry must come from CoreText, not a fixed character grid
- 11 — Example app wipes editor state on every SwiftUI update

## Comments

2026-06-10: Re-blocked after user testing found the editor unusable (no arrow
keys, broken selection geometry, ⌘B inert). The Extension API review needs a
working editor to evaluate keymap entries and Render Hooks against — 09–11
must land first.
