# ADR 0007: Block nesting is real tree depth, indexed by a leaf-block tiling

Date: 2026-06-13

## Status

Proposed

## Context

The Document model and layout engine assume blocks are a flat, depth-1 list.
CONTEXT.md already defines Block Nodes that nest — blockquote, code block, list,
list item — and ADR 0003 commits to Tiptap's node types (`bulletList`,
`orderedList`, `listItem`, `taskList`, `taskItem`, `blockquote`, `codeBlock`),
but the code special-cases depth 1:

- `Document.BlockIndex` is a flat array over `root.content` (`blockStarts`,
  `blockTextCounts`, `blockCharStarts`); `blockInfo(containing:)` binary-searches it.
- `IncrementalLayoutStore.layout` iterates `root.content` as a flat block list
  and emits leaf Layout Boxes under one root container; `blockRange(at:)` assumes
  top-level siblings.
- `GeometryMapper` and `CanvasView` walk `root.children` flatly.
- The Steps' editing algebra addresses blocks by `info.index` and writes via the
  `replacingBlocks(in: Range<Int>)` primitive — sibling top-level blocks only.

Nesting therefore cuts through model → Position index → layout → geometry →
canvas → editing all at once. This ADR records *how* it will be modeled, not a
feature spec; it is filed ahead of implementation so later work (and future
architecture reviews) build on a settled shape.

Two earlier decisions already lean toward nesting: `LayoutBox.Kind` already has
`.container` and `.leafBlock` cases, and ADR 0001 has the container box own each
child's absolute frame and Position range. The layout substrate was designed for
depth; the store and the index were not.

## Decision

**1. Nesting is genuine recursive tree depth — never flattened attrs.** Container
Block Nodes hold child Block Nodes; leaf Block Nodes (paragraph, heading, code
block) hold inline content. We adopt Tiptap's container node types verbatim
(ADR 0003). No `indent`/`depth` attr on a flat paragraph stands in for a list or
a quote.

**2. Positions are unchanged; the derived index generalizes to a leaf-block
tiling.** ProseMirror Positions already count every node boundary at any depth,
so the addressing scheme needs no change. What changes is `BlockIndex`: instead
of tiling the top-level blocks, it tiles the **leaf blocks** — the units CoreText
typesets — in document order, each with its absolute Position range, character
offset, and the container chain (the ancestors needed for indent and decoration).
Leaf blocks still tile the text-Position space contiguously, so position-↔-block
lookup stays a binary search and keystrokes stay O(log leaves), preserving the
invariant the editing-performance work established (see
`.scratch/editing-performance/issues/07`). The container chain is carried
alongside each leaf, not searched.

**3. The layout tree becomes genuinely nested.** `IncrementalLayoutStore` emits
container Layout Boxes that stack child boxes and draw decorations (indent bars,
bullets, ordered numbers, quote rules, code-block backgrounds); leaf boxes
typeset as today. This realizes the container-box case ADR 0001 and CONTEXT
already describe. Incremental reuse keys on subtree Position-range intersection at
every level, so an untouched blockquote or list subtree is reused whole rather
than re-walked.

**4. The block-replace primitive and structural Steps generalize from index to
path.** `replacingBlocks(in: Range<Int>, with:)` becomes a replace of children
within a parent container addressed by a path. Structural Steps gain the
container operations ProseMirror names — wrap / unwrap, lift / sink — on top of
split / join (which now happen within a container: splitting a list item, joining
into the previous sibling). Because the editing algebra was localized in the
Steps (the editing-algebra-into-steps work), this change is concentrated there,
not scattered across `Document`.

**5. Phasing — blockquote first.** Blockquote is the tracer bullet: the simplest
container (one child list of blocks, no markers, no numbering, no per-item
state), so it forces "blocks contain blocks" end-to-end through every layer with
minimal extra semantics. Bullet/ordered lists and task lists (markers, numbering,
checkbox state) and the code block layer on after the recursive substrate is
proven.

## Considered Options

- **Flatten nesting into block-level indent / quote attrs on paragraphs.**
  Rejected: it breaks the Tiptap round-trip (ADR 0003) — Tiptap stores real
  `bulletList` / `listItem` / `blockquote` nodes, so export would be silent
  structural data loss (against the spirit of ADRs 0005–0006). It also cannot
  represent list-item boundaries, per-item task state, or nested lists faithfully.

- **Rebuild the index from scratch per edit for nested documents.** Rejected: it
  re-introduces the O(document) per-keystroke cost the editing-performance epic
  removed; large lists would stall typing again.

- **Switch the layout substrate to per-block layers/views with recycling**
  (ADR 0002's deferred escape hatch). Rejected as part of this work: nesting needs
  a nested box tree, not a different paint model — the viewport-canvas repaint
  (ADR 0002) works unchanged over nested boxes. Keep them orthogonal; revisit
  recycling only if a scroll benchmark forces it.

## Consequences

- The "blocks tile the Position space → binary search" invariant moves from
  depth-1 to "leaf blocks tile the text-Position space." The three parallel binary
  searches in `Document`, `GeometryMapper`, and `Layout` get unified here: the
  leaf-tiling index becomes the single authority. The deferred "unify the block
  search" refactor stops being speculative once this lands — its shape is then
  known.

- Geometry and selection must handle container boundaries: the caret cannot land
  on a container's boundary tokens (no text there), and selecting a whole
  container is a NodeSelection — the same mechanism ADR 0006 defers for Opaque
  Nodes. Nesting and NodeSelection should land together or in close sequence.

- A new CONTEXT term is warranted for the leaf-block tiling (the generalized
  index); add it to CONTEXT.md when the first slice lands.

- Each phase (blockquote, lists, task lists, code block) is its own vertical slice
  and re-validates the editing-performance benchmarks on a nested fixture, since
  the index and reuse paths are exactly what is being generalized.
