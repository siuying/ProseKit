# 03 — Caret placement & range selection by touch

Status: done

## What to build

Make the caret and selection driven by touch and by the document geometry. A user
taps anywhere in the text to place the caret at the nearest valid Position, and
drags to select a range that highlights.

`ProseModel`: the `Selection` protocol with `TextSelection` (anchor Position +
head Position; collapsed = caret) as its only conformer for now. Selection lives
in the editor state and is carried by Transactions.

`ProseEditor`: the `UITextInput` geometry methods that map points ↔ Positions and
Positions ↔ rects — `closestPosition(to:)`, `caretRect(for:)`,
`firstRect(for:)`, `selectionRects(for:)`, and the text-position/text-range
plumbing UIKit needs. Tapping moves the caret; dragging extends a `TextSelection`
whose range is drawn as a highlight under the glyphs. Geometry must be correct
across Line Fragment wrap boundaries within a Box and across Box boundaries.

The iOS selection-handle drag UI, magnifier/floating cursor, and edit menu are
explicitly out of scope (later polish).

## Acceptance criteria

- [ ] Tapping in the text places the caret at the nearest valid Position (verified across wrapped lines and between blocks)
- [ ] Dragging selects a range; the selected range is highlighted under the correct glyphs
- [ ] `closestPosition(to:)` and `caretRect(for:)` are consistent (tapping a caret rect's point returns that Position) — assertable off-screen
- [ ] Selection survives a subsequent edit via `Mapping` (caret/range lands in the right place after an insert/delete)
- [ ] A collapsed `TextSelection` renders as the caret; a non-empty one renders as a highlight

## Blocked by

- 02 — Type into a paragraph
