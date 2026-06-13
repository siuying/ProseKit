# 03 — Move mark-splicing into the mark Steps

Status: ready-for-agent

## What to build

Move the add/remove-mark *semantics* out of `Document` and into the mark Steps,
using the primitive seam from slice 01.

- `AddMarkStep` / `RemoveMarkStep`: move the body of the shared
  `Document.settingMark(from:to:mark:enabled:)` — computing the updated Mark set
  (`MarkRules.adding` when enabling, filter when removing) and splicing the run —
  into a free function beside the mark Steps in `Step.swift`. Each Step's `apply`
  calls it; `inverted` (Add↔Remove) and `map` (identity) stay put.
- Move the `private extension Node` helpers that only the mark algebra uses —
  `splicingTextNode(atPath:replacing:withText:marks:)` and `textNode(atPath:)` —
  out of `Document.swift` to sit with the moved algebra. (Confirm no remaining
  `Document` query depends on them; `rangeHasMark` uses `textNode(atPath:)`, so
  if it stays a Document query the helper stays reachable — see note.)
- The algebra locates the run via the now-`internal` `textRange(from:to:)`
  (slice 01) and writes via `replacingBlocks(in:with:)`.
- `rangeHasMark(from:to:mark:)` stays on `Document` (query; used by
  `EditorState.isActive` and `Commands.toggleMark`).
- Delete `Document.settingMark`, `addingMark`, `removingMark`.

Note: `textNode(atPath:)` is shared by the mark algebra and the `rangeHasMark`
query. Keep it reachable by both — simplest is to leave it as an `internal`
helper on `Document` alongside `textRange`, moving only `splicingTextNode` (which
only the algebra uses). Decide during implementation; the test is that nothing
orphaned remains.

## Acceptance criteria

- [ ] `AddMarkStep` / `RemoveMarkStep` apply via a free function in `Step.swift`;
      apply/inverted/map/algebra co-located
- [ ] `Document.settingMark` / `addingMark` / `removingMark` deleted
- [ ] `Document.rangeHasMark` remains (query)
- [ ] `splicingTextNode` no longer lives on `Document` unless a surviving query
      needs it; no orphaned helpers remain (deletion test)
- [ ] Mark add/remove splits and preserves surrounding runs exactly as before;
      mark exclusion rules unchanged (pinned by `MarkExclusionTests`)
- [ ] `changedRange` for add/remove mark is unchanged
- [ ] Model tests green (incl. `MarkStepTests`, `MarkExclusionTests`)
- [ ] Rendering-equivalence test green for a mark applied across a run boundary
- [ ] Full package suite green

## Blocked by

- `editing-algebra-into-steps/issues/01` (the primitive seam must exist).
  Independent of slices 02 and 04; shares only the `Node` text helpers with 04,
  so landing after 04 (or vice versa) reduces churn but is not required.
