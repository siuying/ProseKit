# 13 — textAlign (+ alignment buttons)

Status: done (model + render); buttons deferred to the toolbar slice

## What to build

The `textAlign` block Attr on paragraph + heading (Q9.2), values
left/center/right/justify, accepted present or absent. Rendering aligns each
Line Fragment's origin; justify stretches every line but the last via
`CTLineCreateJustifiedLine` (CTLine does not justify on its own). An absent or
unrecognised value flushes left (degrade in rendering, never in data — ADR 0005).
`Commands.setTextAlign(_:)` is the headless side; the toolbar buttons land with
slice 07.

## Acceptance criteria

- [x] center / right / justify each render with different line origins than left
- [x] caret/hit-testing follow the shifted origins (Geometry uses the fragment
      frame minX; existing geometry/layout tests stay green)
- [x] `Commands.setTextAlign("center")` sets the Attr; `setTextAlign(nil)` clears it
- [x] `nil`/`"left"` store no redundant Attr; the value round-trips otherwise
- [ ] alignment buttons — deferred to slice 07 (toolbar)

## Blocked by

- 01 — Per-feature format units. (Buttons additionally need 07.)

## Comments

2026-06-12: Alignment is applied in `typesetLineFragments` by computing each
line's x-origin from the block's `textAlign`; because Geometry derives caret and
hit-test x from the fragment's frame, no separate geometry change was needed.
