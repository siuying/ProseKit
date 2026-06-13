# 02 — Move split/join algebra into the structural Steps

Status: ready-for-agent

## What to build

Move the block split and join *semantics* out of `Document` and into the Steps
that own their inverse and mapping, using the primitive seam from slice 01.

- `SplitBlockStep`: move the body of `Document.splitBlock(at:blockType:blockAttrs:)`
  — choosing the two resulting blocks (the first inherits type/Attrs; the second
  takes the override or inherits), computing the split offset, and the
  `changedRange` — into a free function beside `SplitBlockStep` in
  `StructuralSteps.swift`. `apply` calls it; `inverted` (→ `JoinBlocksStep`) and
  `map` stay put.
- `JoinBlocksStep`: move the body of `Document.joinBackward(at:)` — empty-block
  removal vs. run-concatenation merge (Marks preserved across the join), and the
  `changedRange` — into a free function beside `JoinBlocksStep`. The precondition
  query `canJoinBackward(at:)` stays on `Document` (read; used by
  `Commands.joinBackward`).
- Both build their new blocks and call the internal `replacingBlocks(in:with:)`.
- Delete `Document.splitBlock` and `Document.joinBackward`.

After this slice, an entire structural operation (apply + inverted + map +
algebra) reads in one place in `StructuralSteps.swift`.

## Acceptance criteria

- [ ] `SplitBlockStep` and `JoinBlocksStep` apply via free functions in their own
      file; `apply`/`inverted`/`map`/algebra co-located per Step
- [ ] `Document.splitBlock` and `Document.joinBackward` are deleted
- [ ] `Document.canJoinBackward(at:)` remains (query)
- [ ] Marks survive a non-empty join exactly as before (run concatenation, not
      plain-text merge)
- [ ] `changedRange` for split and join is unchanged
- [ ] Round-trip holds: split then join (and join then split via inversion)
      returns the original Document, index included
- [ ] Rendering-equivalence tests green for split and join at document start,
      middle, and end
- [ ] Full package suite green

## Blocked by

- `editing-algebra-into-steps/issues/01` (the primitive seam must exist).
  Independent of slices 03 and 04.
