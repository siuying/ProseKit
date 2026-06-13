# 04 — Move replace/run-cut algebra into `ReplaceStep`

Status: ready-for-agent

## What to build

Move the heaviest edit — text replacement, including the cross-run/cross-block
merge — out of `Document` and into `ReplaceStep`, completing the deepening.

- `ReplaceStep`: move the body of `Document.replacingText(from:to:with:marks:)`
  and the `Document.replacingAcrossRuns(...)` branch it falls through to — the
  same-run splice, the marked-insertion-at-caret case, and the cross-boundary
  merge (head runs + inserted run + tail runs into one block of the first's
  type, Marks preserved) — into a free function beside `ReplaceStep` in
  `Step.swift`. `apply` calls it; `inverted` (re-`ReplaceStep` over the deleted
  text) and `map` stay put.
- Move the `private extension Node` helpers this algebra uses —
  `inlineRuns(upTo:)`, `inlineRuns(from:)`, `replacingTextNode(atPath:with:)`,
  and `splicingTextNode` if not already relocated by slice 03 — out of
  `Document.swift` to sit with the algebra.
- The algebra locates the run via the `internal` `textRange(from:to:)`
  (slice 01) and writes via `replacingBlocks(in:with:)` /
  `replacing(root:blockAt:)` (fold the single-block path into the primitive if
  convenient).
- Delete `Document.replacingText`, `Document.replacingAcrossRuns`, and the
  now-unused `text(from:to:)` only if nothing else needs it (the Step inverse
  uses it — keep it `internal` if so).

After this slice, `Document`'s surface is queries + `replacingBlocks`; no
edit-*choosing* method remains. Verify the deletion test holds across the whole
file: every former edit method is gone and its algebra reads beside its Step.

## Acceptance criteria

- [ ] `ReplaceStep` applies via a free function in `Step.swift`;
      apply/inverted/map/algebra co-located
- [ ] `Document.replacingText` and `Document.replacingAcrossRuns` deleted; the
      `Node` run-cut helpers (`inlineRuns`, `replacingTextNode`) no longer live
      on `Document`
- [ ] Cross-block backspace and typing-over-a-multi-block-selection behave
      exactly as before (cross-boundary merge keeps outside runs and Marks)
- [ ] Marked insertion at a collapsed caret still rides the inserted run only
- [ ] `changedRange` for same-run and cross-run replace is unchanged
- [ ] `Document`'s remaining surface is queries + `replacingBlocks` — no
      edit-choosing methods left (deletion-test sweep of `Document.swift`)
- [ ] Model tests green (incl. `ReplaceStepTests`, `TransactionTests`,
      `PositionTests`, `DerivedIndexTests`)
- [ ] Rendering-equivalence tests green for insert, shrink-delete, cross-block
      delete, and cross-block replace at start, middle, and end
- [ ] Full package suite green

## Blocked by

- `editing-algebra-into-steps/issues/01` (the primitive seam must exist).
  Independent of slices 02 and 03; shares the `Node` text helpers with 03, so
  whichever lands second relocates whatever the first left behind.
