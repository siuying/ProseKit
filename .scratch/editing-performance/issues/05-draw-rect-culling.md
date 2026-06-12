# 05 — Draw-rect culling on the editing path

Status: ready-for-human

## What to build

Make `ProseView.draw(_:)` cost proportional to the dirty region instead of
the document, and make edit paths request block-accurate dirty rects
instead of `setNeedsDisplay()` on the whole view.

The README originally deferred draw-rect culling to a future slice
(alongside scrolling). Pulled forward 2026-06-12 by the maintainer after
issue 04's instrumentation showed the full-document repaint is the largest
remaining per-keystroke cost on the live path.

### Why

`draw(_:)` iterates every block's Line Fragments and issues a `CTLineDraw`
per fragment, ignoring the dirty `rect`. Every keystroke calls
`setNeedsDisplay()` with no rect, so each key repaints the whole document:
~4 ms at 800 paragraphs (issue 04 trace), linear in document size, against
the 8.3 ms / 120 Hz budget. Two separate wastes:

1. Blocks entirely outside the view's bounds are still drawn (the view has
   no scroll container; everything below the first screenful is invisible).
   Culling alone makes draw O(visible blocks) even with a full dirty rect.
2. A one-character edit dirties only its block (or the tail below it when
   heights change), but the whole visible region re-rasterizes. Block-level
   dirty rects keep typing repaints to one block.

### Design

- **Cull in draw.** Skip any block whose frame does not intersect the
  incoming `rect`. Container-level frames are absolute (see
  `docs/adr/0001-box-relative-layout-fragments.md`), so this is one
  `CGRect.intersects` per block — no new geometry. Blocks are y-ordered;
  an early exit after the first non-intersecting block past the rect is
  free to take, but O(blocks) intersection checks are noise (README
  decision 2 precedent).
- **Dirty rects from edits.** After `relayout(changedRange:)`, compute the
  union of the changed blocks' new frames and pass it to
  `setNeedsDisplay(_:)`. When the document's total height changed or the
  block count changed (split/join), extend the dirty rect from the first
  changed block's top to the bottom of the previous and new layout —
  everything below moved. Conservative over-invalidation is acceptable;
  a too-small rect is a correctness bug (stale pixels), so the fallback
  for any path without a Changed Range stays `setNeedsDisplay()`.
- The caret/selection chrome is UIKit's (`UITextSelectionDisplayInteraction`
  owns its own layers); no Prose drawing depends on selection state, so
  selection changes need no Prose repaint.

### Verification focus

Stale-pixel bugs are the failure mode culling invites. Pin with a
rasterization correctness test before optimizing: render, edit mid-document
(insert, split, join at a block whose height changes), render again, and
compare against a freshly created view's rendering of the same document —
they must match pixel-for-pixel.

### New benchmark (red/green signal)

Typing benchmarks never rasterize — issue 04's post-mortem lesson is that
the benchmark must do what the platform actually does. Add a draw-inclusive
typing benchmark: per keystroke, `insertText` then render the dirty region
the way UIKit would (layout pass + `UIGraphicsImageRenderer` draw of the
view). Record before/after in this issue's comments.

## Out of scope

- Scrolling / viewport management — still a future slice. Culling against
  `bounds` is this issue; culling against a scroll offset is that slice.
- Layer-backed incremental rendering (CATiledLayer etc.) — not warranted at
  prose scale.
- deleteBackward variance — issue 06.

## Acceptance criteria

- [ ] Draw-inclusive typing benchmark exists; many-pages number recorded
      before and after
- [ ] Per-keystroke draw work is proportional to the dirty region: typing
      repaints one block; split/join repaints from the edit downward only
- [ ] Rasterization equivalence test: edited view renders identically to a
      fresh view of the same document (insert, split, join cases)
- [ ] All existing benchmarks hold (typing scenarios, interaction path,
      initial render, full layout)
- [ ] All package tests green

## Blocked by

None (builds on the issue 04 branch; coordinate with the open PR stack
#10 → #13).

## Comments

### 2026-06-12 — implemented

Branch: `editing-performance-05-draw-rect-culling`

- `draw(_:)` culls to the dirty rect with an early break (blocks are
  y-ordered); `ProseView.editDirtyRect` computes the edit invalidation
  (changed blocks' frames, full-width strip, ±2 pt glyph outset, extended
  to the taller layout's bottom when total height or block count changes);
  all four edit paths route through `relayoutAndDisplayEdit()`. Anything
  without a Changed Range still invalidates the full bounds.
- New benchmark `testTypingWithDrawHostileSizeProse` (880 blocks, one
  rasterized screen per keystroke, scale 1): red 29 ms/key average
  (first-iteration 92 ms/key) → green **8.8 ms/key, rsd 4.6%**. The
  benchmark renders via `layer.render`, which always draws the full
  bounds, so it measures culling only; the live path also benefits from
  the narrower dirty rects, which `layer.render` cannot exercise.
- Correctness pinned in `RenderingTests`: edited view renders
  byte-identically to a fresh view (mid-block insert, split, join,
  shrinking delete), partial-rect draw matches full draw inside the rect,
  and `editDirtyRect` unit tests (single-block strip for a no-reflow
  edit, taller-bottom extension for a split, full-bounds fallback).
- Full suite green: 61 iOS package tests; all other benchmarks held
  (typing-at-end 1.1 ms/key rsd 2%, interaction path 2.5 ms/key rsd 3.4%,
  initial render and full layout unchanged).
