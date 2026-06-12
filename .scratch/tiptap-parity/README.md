# Tiptap Simple Editor parity

Expanding the Prose editor to Tiptap's "Simple Editor" format set. Design
decisions live in `CONTEXT.md` (glossary) and `docs/adr/0003`–`0006`; this
directory holds the implementation issues.

## Status

| # | Title | Status |
|---|-------|--------|
| 01 | Per-feature format units + unknown-mark preservation | done |
| 02 | Strike + underline marks | done |
| 03 | Highlight mark (multicolor, parse-or-plain, dark mode) | done |
| 04 | Mark exclusion + superscript/subscript | done |
| 05 | Link mark + paste-URL-onto-selection | done |
| 06 | Active-state API + level-aware headings | done |
| 13 | textAlign | done (model+render; buttons with 07) |
| 17 | Input rule engine + heading rules | done (engine+headings; rest deferred) |
| 07 | Packaged toolbar core | ready-for-agent (UI) |
| 08 | Link popover | ready-for-agent (UI) |
| 09 | Highlight palette popover | ready-for-agent (UI) |
| 10 | Blockquote — block-nesting pathfinder | ready-for-agent (deep model) |
| 11 | hardBreak | ready-for-agent (position model) |
| 12 | codeBlock | ready-for-agent (newline layout) |
| 14 | Bullet + ordered lists | ready-for-agent (needs 10) |
| 15 | Task lists | ready-for-agent (needs 14) |
| 16 | Hardware keyboard shortcuts | ready-for-agent (UI) |
| 18 | Opaque Nodes + NodeSelection | ready-for-agent (needs 10) |
| —  | Undo/redo history | see `prose-slice-1/07` (amended) |

## Done vs. ready-for-agent

Slices 01–06, 13, and 17(engine) are implemented test-first and green on the
booted simulator (`zsh .scratch/tiptap-parity/rt.sh -only-testing:…`). They
cover the entire inline-Mark layer plus text alignment, active-state queries,
and the input-rule engine.

The remaining slices are filed ready-for-agent with the design decisions baked
in. They divide into:

- **Deep model/layout** (10 nesting, 11 inline-leaf, 12 newline layout, 14/15
  lists/tasks, 18 opaque nodes) — each extends the Position/layout model beyond
  the current flat-text-blocks assumption.
- **UIKit UI** (07 toolbar, 08/09 popovers, 16 keyboard) — headless cores are
  test-first; the chrome needs app verification.
- **History** — `prose-slice-1/07`, amended here: needs the command layer to emit
  invertible Steps first (it currently bypasses them via `replaceDocument`).
