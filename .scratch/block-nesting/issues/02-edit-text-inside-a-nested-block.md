# 02 — Edit text inside a nested block

Status: ready-for-agent

## What to build

Typing, autocorrect, and Backspace inside a leaf block that lives in a container
behave exactly as they do in a top-level paragraph. This generalizes the
block-replace primitive from a flat block index to a **path**.

End-to-end behavior:

- The block-replace primitive addresses children within a parent container by
  path (`replacingBlocks` becomes a replace of a child range under a parent
  addressed by `[Int]`), and derives the new leaf-block index incrementally:
  a text edit changes one leaf's count and shifts following leaves by a constant
  delta, leaving paths untouched — the O(log) keystroke invariant.
- `ReplaceStep` (and the mark Steps) operate unchanged at the Step level; only
  the algebra they call learns about paths.
- Incremental layout reuse recurses: an untouched container subtree is reused
  with a y/Position shift; only the edited leaf re-typesets.

Insert/delete/replace within a quoted paragraph produce the same Document,
`changedRange`, and rendering as the same edit in a top-level paragraph.

## Acceptance criteria

- [ ] Typing, deleting, and replacing a selection **within** a quoted paragraph
      match the equivalent top-level edit (Document, selection, `changedRange`)
- [ ] The derived leaf-block index after a nested text edit matches a
      from-scratch rebuild (`DerivedIndexTests`, nested fixture)
- [ ] Incremental layout reuses the untouched container subtree and untouched
      sibling leaves; only the edited leaf re-typesets (assert via typesetID)
- [ ] Rendering-equivalence for insert / shrink-delete inside a blockquote at the
      first, middle, and last quoted block
- [ ] Keystroke perf on a nested fixture holds (no O(document) term)
- [ ] Full package suite green

## Blocked by

- `block-nesting/issues/01` (the leaf-block index and nested layout must exist).
