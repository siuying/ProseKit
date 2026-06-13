# 01 — Render a static nested document (blockquote)

Status: ready-for-human

Type: HITL — this is the foundation; the index/layout shape it locks is
perf-critical and warrants design review in the PR. The data-structure decisions
are resolved (ADR 0007 + the slice-01 review captured in the feature README); the
human checkpoint is confirming the implementation honors them and holds the
keystroke perf invariant.

## What to build

The recursion tracer bullet, read-only: a Tiptap document containing a
`blockquote` (itself containing paragraphs/headings) **loads, renders with a
quote rule + indent, and accepts caret placement inside the nested blocks** — no
editing yet. This proves the document tree, the index, the layout tree, the
Canvas, and geometry all work at depth > 1.

End-to-end behavior:

- The Schema accepts `blockquote` as a container Block Node holding Block Nodes.
- `BlockIndex` enumerates **leaf blocks** at any depth (the resolved leaf-block
  tiling: per-leaf text-Position range, character offset, and `[Int]` path from
  root; container nodes recovered by walking `root` + path). Leaf ranges are
  ordered, disjoint, monotonic; binary-search Position-↔-leaf lookup holds.
- `IncrementalLayoutStore` emits genuinely nested **container** Layout Boxes
  (`LayoutBox.Kind.container`) that stack child boxes; leaf boxes typeset as
  today.
- The Canvas walks the box tree depth-first and draws the blockquote's decoration
  (indent + quote rule) in the container box's frame before its children.
- `GeometryMapper` places the caret and maps points to Positions inside nested
  leaves; the caret never lands on a container boundary token.

No mutation paths change in this slice (editing arrives in 02). Full document
layout / `contentSize` still come from the root box height (ADR 0002 unchanged).

## Acceptance criteria

- [ ] A Tiptap JSON doc with a `blockquote` of two paragraphs loads (round-trips
      on re-export, ADR 0003) and renders with an indent + quote rule
- [ ] `Document` queries (`blockInfo`/leaf lookup, position arithmetic,
      `totalTextCount`) return correct results for the nested doc; index matches a
      from-scratch rebuild (extend `DerivedIndexTests` with a nested fixture)
- [ ] Caret can be placed in either quoted paragraph and at the trailing
      top-level paragraph; `closestPosition`/`caretRect` round-trip; the caret
      never resolves to a container boundary token
- [ ] Rendering-equivalence: the nested doc renders identically whether laid out
      fresh or via the store
- [ ] Keystroke-path perf benchmark on a nested fixture shows Position↔leaf
      lookup stays O(log leaves) (no per-edit O(document) walk reintroduced)
- [ ] iOS simulator screenshot confirms the blockquote renders with the expected
      indent/rule (use the verify-ios-simulator skill)
- [ ] Full package suite green

## Blocked by

None - can start immediately. Implements ADR 0007; the leaf-index payload is
"path only" per that ADR. Covers tiptap-parity issue 10 (render half).
