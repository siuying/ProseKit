# 01 — Establish the block-replace primitive seam; migrate the block-attr Steps

Status: ready-for-agent

## What to build

Reshape `Document`'s edit surface so a Step owns its own algebra, and prove the
pattern end-to-end on the two simplest Steps.

`Document` currently holds six edit methods that only their matching Step calls,
backed by one private write primitive (`replacingBlocks(in:with:)`) over the
private block-index machinery. This slice exposes that primitive as the seam and
migrates the first two operations across it:

- Make `replacingBlocks(in:with:)` reachable by Steps (it stays in the same
  target — `internal` visibility is enough; no public API change). The private
  `BlockIndex` / `derivedIndex` / `makeIndex` machinery behind it stays private
  and unchanged — this is the O(log blocks) keystroke invariant.
- Make `textRange(from:to:)` `internal` so migrated Steps can locate a text node
  through it (locked decision: `textRange` stays on Document as a shared query
  helper; it also backs the `rangeHasMark` query).
- Migrate `SetBlockTypeStep` and `SetTextAlignStep`: move the body of
  `Document.settingBlockType(at:headingLevel:)` and
  `Document.settingTextAlign(at:to:)` into a free function beside each Step in
  `StructuralSteps.swift` (locked decision (b): free function per Step, in the
  Step's own file). `apply` becomes a one-liner into that function, sitting next
  to the Step's existing `inverted` and `map`. Delete the two now-unused
  `Document` methods.

This is the tracer bullet: it cuts the full pattern — expose primitive → algebra
as a free function beside the Step → delete the Document method → suite stays
green — on the cheapest case (single-block replace, Positions stable).

## Acceptance criteria

- [ ] `replacingBlocks(in:with:)` and `textRange(from:to:)` are `internal`; the
      `BlockIndex` / `derivedIndex` / `makeIndex` machinery remains `private`
- [ ] `SetBlockTypeStep.apply` and `SetTextAlignStep.apply` call a free function
      in `StructuralSteps.swift`; their `apply`/`inverted`/`map` are co-located
- [ ] `Document.settingBlockType` and `Document.settingTextAlign` are deleted
      (deletion test: nothing else references them)
- [ ] No change to the `Step` protocol surface or any public Document API
- [ ] `changedRange` returned by both Steps is unchanged (same blocks reported)
- [ ] Model tests green (incl. `TransactionTests`, `DerivedIndexTests`)
- [ ] Rendering-equivalence tests green for a heading toggle and a text-align
      change (edited view renders identically to a fresh view)
- [ ] Full package suite green

## Blocked by

None - can start immediately.
