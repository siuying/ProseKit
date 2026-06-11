# 02 — Block-relative geometry, O(block) offset math

Status: ready-for-agent

## What to build

Store each Layout Box's Line Fragment geometry and Position ranges *relative
to the box*, so reusing a block across an edit is free — no per-fragment
remapping at all — and rewrite the UITextInput offset/geometry math to be
O(block) instead of O(document) per call. Ship with an ADR for the
coordinate-space decision.

### Why

Issue 01 makes reuse *fire*; this issue makes it *free* and extends the win
to the paths UIKit hits around every keystroke in production:

- Even with issue 01's zero-delta fast path, every block *below* an edit
  still pays a full Line Fragment array rebuild in
  `shifted(toY:positionRange:)` — O(document) allocation per keystroke,
  merely cheaper than re-typesetting. With box-relative fragments, a reused
  block is a struct copy and the only thing that moves is the container's
  running y/Position cursor.
- `characterOffset(of:)` / `position(atCharacterOffset:)` walk every block
  and rebuild `block.plainText` (a fresh String join) per call; `clamp()`
  calls `endTextPosition`, which walks the whole tree. UIKit calls
  `caretRect`, `selectionRects`, `firstRect`, tokenizer context reads, and
  `position(from:offset:)` around every keystroke — none of it measured by
  the pre-issue-01 benchmarks. The interaction-path benchmark issue 01 adds
  is this issue's red/green signal.

This was deliberately split from issue 01 (strict sequencing): if the
benchmark misses with both changes fused, you cannot tell which half is
wrong, and this is the half with subtle failure modes (caret in the wrong
block, selection rects off by one boundary).

### Geometry model

- A leaf Layout Box's Line Fragments carry frames and Position ranges
  relative to *their box's* origin and range start.
- The container owns each child's absolute origin and absolute Position
  range (the running cursor it already computes).
- `LayoutBox.shifted(toY:positionRange:)` is deleted — nothing needs
  shifting anymore. Issue 01's zero-delta fast path goes with it.
- `GeometryMapper`, `draw(_:)`, `caretRect`, `selectionRects`, `firstRect`,
  and `closestPosition` convert between box-local and view coordinates at
  the boundary — one add/subtract at the box level, never a rewrite of
  fragment arrays.

### Offset math becomes O(block)

- Cache `endTextPosition` (and, if useful, block-size prefix sums) as lazily
  computed derived state on Document. Document is immutable — editing
  produces a *new* Document — so there is no invalidation problem to design;
  the cache cannot go stale.
- `characterOffset(of:)` / `position(atCharacterOffset:)` and `text(in:)`
  walk node text in place instead of materializing `plainText` joins per
  block per call. Target: locating a Position costs a walk to one block plus
  work proportional to that block's text, not the document's.

### ADR

Write `docs/adr/` entry for the box-relative coordinate space. It meets all
three bars: hard to reverse (every geometry consumer assumes the
convention), surprising without context (absolute rects are the UIKit norm),
and a real trade-off (absolute coordinates make reads trivial and edits
O(document); box-relative inverts that, which is the right trade for an
editor where edits are the hot path).

### Verification focus

The position-mapping math around block boundaries is the known-fragile area
(block boundaries are two Positions but read as one "\n" in character
space — see the UITextInput offset-math fix in git history). Every boundary
behavior that exists today must be pinned by a test before the rewrite, not
discovered after: caret at block start/end, selection spanning blocks,
`offset(from:to:)` across boundaries, tokenizer round-trips at boundaries.

### Out of scope

- Augmented tree for Position/Y lookups — rejected for now (Runestone needs
  it at 100K lines; prose-scale documents do not). Revisit only if the
  README's tripwire (~2,000-block benchmark breaking ~1 ms/key on the walk)
  fires.
- Scrolling, draw-rect culling — future slice.
- Typing-at-start anomaly — issue 03.

## Acceptance criteria

- [ ] Interaction-path typing benchmark, many pages: ≤ 8.3 ms/key total
      (recorded baseline from issue 01 as the before)
- [ ] rsd ≤ 20% on all typing scenarios
- [ ] All issue-01 benchmark results hold or improve (typing-at-end,
      paragraph breaks, initial render)
- [ ] `LayoutBox.shifted` is gone; reusing a block performs no per-fragment
      work
- [ ] Locating a Position (caret rect, offset math, `text(in:)`) does work
      proportional to one block, not the document; no `plainText` joins on
      per-keystroke paths
- [ ] `endTextPosition` is O(1) after first computation on a given Document
- [ ] Block-boundary mapping tests pass: caret at block start/end, selection
      spanning blocks, `offset(from:to:)`/`position(from:offset:)`
      round-trips across boundaries, tokenizer word selection at boundaries
- [ ] All existing ProseEditor/ProseModel tests green
- [ ] ADR for the box-relative coordinate space committed under `docs/adr/`

## Blocked by

- 01 — Incremental relayout on every edit path (benchmarks must be green
  first; strict sequencing decision, see README)
