# 09 — Highlight palette popover + customizable palette API

Status: ready-for-agent

## What to build

The highlight UX on top of the `highlight` Mark (slice 03) and toolbar (07), per
Q7. The default swatch palette already exists as `HighlightColor.darkModePalette`
keys; this slice surfaces it and makes it customizable.

- Toolbar highlight button opens a popover of swatches (the shipped default
  palette) plus a "none" / clear option.
- Selecting a swatch applies `highlight` with that colour (`Commands.toggleMark`
  / a `setHighlight(color:)` command) over the selection.
- A public API lets the host app supply its own palette (colours + their
  dark-mode variants), replacing the default.

## Acceptance criteria

- [ ] a default swatch palette is presented from the toolbar
- [ ] selecting a swatch applies that highlight colour to the selection; "none"
      clears it
- [ ] the host app can replace the palette via a public API; the popover and the
      dark-mode mapping use the supplied palette
- [ ] applying a highlight is undoable

## Blocked by

- 03 — Highlight mark.
- 07 — Packaged toolbar.

## Comments

2026-06-12: ready-for-agent. Promote `HighlightColor`'s built-in palette to a
configurable type the popover and the draw-time resolution both read. Popover UI
needs app verification; the `setHighlight` command + palette config are
test-first.
