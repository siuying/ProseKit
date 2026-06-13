# 05 — Ordered list + nested-list indent/outdent

Status: ready-for-agent

## What to build

Ordered lists with numbering, and nesting of lists via indent/outdent —
completing tiptap-parity issue 14. This is where the **sink** operation (the
counterpart to slice 03's lift) and ordinal computation arrive.

End-to-end behavior:

- The Schema accepts `orderedList` (container of `listItem`), carrying the Tiptap
  `start` attr where present.
- An `orderedList` item's container box draws its **ordinal** instead of a
  bullet. The ordinal is derived at layout time from the item's index among its
  siblings (walking `root` + the leaf's path — no number cached in the model),
  honoring `start`.
- **Tab** at the start of a list item **sinks** it into the preceding item as a
  nested list; **Shift-Tab** **lifts** it one level out. Nested lists render with
  deeper indent and (for ordered lists) restart numbering per level.
- Numbering recomputes correctly after sink/lift, item insert/delete, and
  reorder — always derived, never stored stale.

`SinkStep` joins `LiftStep`/`WrapInStep` as a co-located structural Step. Nesting
exercises the recursive index/layout/reuse paths at depth > 2.

## Acceptance criteria

- [ ] A Tiptap `orderedList` (incl. non-1 `start`) loads, round-trips, and
      renders with correct ordinals
- [ ] Tab sinks an item into a nested list; Shift-Tab lifts it out; both invert
      and map Positions correctly
- [ ] Ordinals recompute correctly after sink/lift and after item insert/delete
      (derived from sibling index, never stored)
- [ ] Nested lists (depth > 2) render with per-level indent and numbering; the
      leaf-block index and layout reuse hold at that depth
- [ ] Rendering-equivalence across sink / lift / renumber; iOS simulator
      screenshot confirms nested numbering
- [ ] Keystroke perf on a deeply-nested fixture holds
- [ ] Full package suite green

## Blocked by

- `block-nesting/issues/04` (list-item container machinery + markers).
