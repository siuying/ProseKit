# Editing algebra into Steps

From the architecture review (2026-06-13), candidate 1: **"The editing algebra
is trapped inside `Document`."**

`Document` carries six edit methods (`splitBlock`, `joinBackward`,
`settingBlockType`, `settingTextAlign`, `replacingText`/`replacingAcrossRuns`,
`settingMark`) that are called *only* by the matching Step's `apply`, while
those Steps are shallow pass-throughs. So each edit's `apply` semantics live in
`Document`, while its `inverted` and `map` live in the Step — one operation
split across two files. `Commands.swift` already documents the intended shape
("the Document only applies Steps; it never chooses"), but today Document does
the choosing.

## The deepening

Reshape Document's interface so the Steps own their whole behaviour:

- **Document keeps** the indexed tree, its queries (`blockInfo`, `textCount`,
  position arithmetic, `rangeHasMark`), and one write primitive,
  `replacingBlocks(in:with:)`, backed by the private `BlockIndex` / `derivedIndex`
  machinery (the O(log blocks) keystroke invariant — stays private, untouched).
- **Steps gain** the edit semantics (the *choosing*): a free function beside
  each Step computes the new blocks and calls `replacingBlocks`; `apply` is a
  one-liner into it, sitting next to that Step's `inverted` and `map`.
- The `private extension Node` helpers in `Document.swift` (`splicingTextNode`,
  `inlineRuns`, `replacingTextNode`) move out with the algebra that uses them.

## Locked decisions

- **(b)** The algebra lands as a **free function per Step in the same file as
  the Step** — not inlined into the `apply` body, not in a separate shared
  editing module. Locality target: one operation, one file.
- **`textRange(from:to:)` stays `internal` on `Document`** as a shared query
  helper. It is used by both the algebra and the `rangeHasMark` query, and "where
  is this text node" is a read, not a choice.

## Scope boundary

Entirely within the `ProseModel` target. The `Step` protocol surface
(`apply` / `inverted` / `map`) does not change, so `EditorState`, `Commands`,
and `ProseView` are untouched. `replacingBlocks` only needs `internal`
visibility (Steps share the module) — no public API change. Every slice is a
green-to-green refactor pinned by the existing model and rendering-equivalence
tests; the `changedRange` each method returns is load-bearing (drives
incremental relayout and the dirty rect) and must be preserved verbatim.

## Slices

1. `01` — Establish the block-replace primitive seam; migrate the block-attr Steps
2. `02` — Move split/join algebra into the structural Steps (blocked by 01)
3. `03` — Move mark-splicing into the mark Steps (blocked by 01)
4. `04` — Move replace/run-cut algebra into `ReplaceStep` (blocked by 01)

02, 03, and 04 depend only on 01 and are otherwise independent.
