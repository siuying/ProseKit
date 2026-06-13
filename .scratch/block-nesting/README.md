# Block nesting

Make the Document and layout trees genuinely recursive so container Block Nodes
(blockquote, lists, list items) work end to end. Implements **ADR 0007**
(`docs/adr/0007-block-nesting-real-tree-depth.md`) and the tiptap-parity feature
issues 10 (blockquote), 14 (bullet/ordered lists), 15 (task lists). Code block is
*not* here — it's a leaf block, tracked by tiptap-parity issue 12.

## The change

Today blocks are a flat, depth-1 list, special-cased in `Document.BlockIndex`,
`IncrementalLayoutStore`, `GeometryMapper`, `CanvasView`, and the Steps' algebra.
This epic generalizes all of them to arbitrary depth, blockquote-first as the
walking skeleton.

## Resolved design (ADR 0007 + the slice-01 HITL review)

- **Leaf-block tiling index.** `BlockIndex` enumerates the **leaf blocks** (the
  CoreText typeset units) in document order. Each leaf carries its absolute
  text-Position range, character offset, and a **path** (`[Int]` child indices
  from the root). Container nodes and decoration data (indent depth, list
  ordinal, quote nesting) are recovered by walking `root` + path on demand —
  never duplicated into the index. This is the ProseMirror-faithful choice: the
  tree stays the single position authority; the index only caches an ordering
  over it (ProseMirror itself has no leaf index — it resolves on demand with a
  12-slot cache and lets the browser lay out).
- **Ranges are ordered, disjoint, monotonic — not contiguous.** Container
  open/close tokens sit in the gaps between leaves; a Position in a gap is
  structural (handled by each Step's `map`, the caret clamping over it).
  Position-↔-leaf lookup stays a binary search → keystrokes stay O(log leaves).
- **Incremental derivation by edit kind.** A text edit (`ReplaceStep` inside a
  leaf) changes one leaf's count and shifts following leaves by a constant —
  identical to today. A structural edit recomputes the index for the affected
  subtree only.
- **Layout reuse recurses.** At each container level, a child box whose Position
  range does not intersect the mapped Changed Range is reused with a y/Position
  shift; an untouched subtree is skipped whole.
- **Decoration is the container Layout Box's job** (`LayoutBox.Kind.container`
  already exists): the Canvas walks the box tree depth-first; each container
  paints its rule/bullet/number/checkbox in its frame before its children.

## Slices

1. `01` — Render a static nested document (blockquote) — **HITL** (foundation)
2. `02` — Edit text inside a nested block (blocked by 01)
3. `03` — Split/join inside a blockquote; wrap & unwrap (blocked by 02)
4. `04` — Bullet list: render markers + item editing (blocked by 03)
5. `05` — Ordered list + nested-list indent/outdent (blocked by 04)
6. `06` — Task lists (blocked by 04)

Linear 01→02→03→04→05; slice 06 branches off 04. Each slice re-validates the
editing-performance benchmarks on a nested fixture, since the index and reuse
paths are exactly what is being generalized.

## Boundary

Whole-container selection rides on **NodeSelection**, which ADR 0006 defers for
Opaque Nodes; these slices handle only caret/text behavior across container
boundaries (caret never lands on container tokens). Full NodeSelection is a
shared cross-cutting slice, sequenced with the Opaque Node work, not here.
