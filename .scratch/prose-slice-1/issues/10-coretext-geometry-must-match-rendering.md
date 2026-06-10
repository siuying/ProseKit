# 10 — Geometry must come from CoreText, not a fixed character grid

Status: done

## Problem

Reported testing the example app after 05 landed: text selection is not
functional — taps place the caret in the wrong place and highlights don't sit
under the glyphs.

Geometry and rendering disagree about where text is:

- `LayoutEngine`/`IncrementalLayoutStore` (`Sources/ProseEditor/Layout.swift`)
  build `LineFragment`s on a fictional monospace grid — hardcoded
  `characterWidth: 10`, line breaks every `width / 10` characters
  (`makeLineFragments`). No CoreText is used despite the import.
- `GeometryMapper` (`Sources/ProseEditor/Geometry.swift`) maps points ↔
  Positions on that same 10pt grid.
- But `ProseView.draw` renders each block via `NSAttributedString.draw(in:)`
  with real proportional fonts (17pt body / 28pt heading, bold/italic/mono
  variants), which wraps and advances per real font metrics.

So caret rects, tap targets, and selection rects are self-consistent (the
GeometryTests pass) but wrong relative to everything on screen — line breaks
don't even fall in the same places. Issue 03's acceptance criteria are not
actually met on-screen; this is the gap.

## What to build

The real CoreText typesetting layer the slice README promises:

- Typeset each leaf block with `CTFramesetter`/`CTTypesetter` from the same
  attributed string used for drawing (extract `ProseView.attributedString(for:)`
  so layout and drawing share one source of truth, mark Render Hooks included).
- `LineFragment` derives from `CTLine`: frame from line origin + typographic
  bounds, `positionRange` from `CTLineGetStringRange` mapped into document
  Positions.
- `GeometryMapper` answers via the line's `CTLine`:
  `CTLineGetOffsetForStringIndex` for caret x, `CTLineGetStringIndexForPosition`
  for hit-testing; selection rects from per-line offset pairs.
- `ProseView.draw` draws the stored `CTLine`s (or at minimum draws per line
  fragment) so what is measured is exactly what is drawn.
- Keep the incremental reuse behavior of `IncrementalLayoutStore` (typeset
  Boxes are cached and reused when their position range is untouched).

## Acceptance criteria

- [ ] Line breaks in `LineFragment`s match the rendered line breaks exactly (same typesetting path)
- [ ] Tapping a glyph places the caret at that glyph's boundary in the example app, including in bold/italic/code runs and headings
- [ ] Selection highlights sit under the selected glyphs across wrap and block boundaries
- [ ] `closestPosition`/`caretRect` round-trip holds with proportional fonts (unit-tested off-screen against CTLine measurements)
- [ ] No `characterWidth` constant remains in layout or geometry

## Blocked by

- 03 — Caret placement & range selection
- 05 — Inline marks: bold / italic / code

## Comments

2026-06-10: Done. Blocks are typeset with CTTypesetter from a shared
BlockStyle attributed string (CTFont per mark set); LineFragments carry their
CTLine, GeometryMapper answers caret/hit-test/selection via
CTLineGetOffsetForStringIndex / CTLineGetStringIndexForPosition (UTF-16 ↔
Character conversion handled), and ProseView.draw draws the stored lines —
one typesetting source of truth. IncrementalLayoutStore reuse now shifts
fragment frames and position ranges when earlier blocks change. characterWidth
is gone. Covered by GeometryTests/LayoutTests/EditorStateTests on macOS.
