# ADR 0001: Box-relative layout fragments

Date: 2026-06-11

## Status

Accepted

## Context

`LayoutBox` reuse is the hot path for editing large prose documents. With
absolute `LineFragment` frames and absolute Position ranges, reusing a block
below an edit still requires rebuilding every fragment in that block to shift
its y coordinate and remap its Position range.

That made reuse cheaper than re-typesetting, but not free. UIKit also asks for
caret, selection, and offset geometry around every keystroke, so the layout
representation should make the edit path cheap without making those reads
ambiguous.

## Decision

Leaf `LayoutBox` children store their `LineFragment` frames and Position ranges
relative to the box:

- `LineFragment.frame` is in the box coordinate space.
- `LineFragment.positionRange` is relative to `LayoutBox.positionRange.lowerBound`.
- The container owns each child box's absolute frame and absolute Position range.
- Geometry consumers convert at the boundary by adding the owning box's origin
  and Position lower bound.

## Consequences

Reusing an unchanged block no longer rewrites its fragment array. The layout
store updates the reused box's absolute frame and Position range, and the
fragment geometry remains valid because it is local to the box.

The trade-off is that geometry reads must carry the owning box while inspecting
a fragment. This is a small amount of boundary conversion in exchange for making
the edit hot path avoid per-fragment allocation and remapping.

Absolute fragment coordinates are deliberately not part of the layout model.
Consumers that need view coordinates must ask through `GeometryMapper` or do the
same box-level conversion explicitly.
