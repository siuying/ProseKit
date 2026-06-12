# 06 — Active-state API + level-aware heading rendering

Status: done

## What to build

Two things the toolbar (slice 07) needs:

- **Active-state API** on `EditorState` (Q4c, public):
  - `isActive(_ mark:)` — the whole selection carries the Mark, or at a collapsed
    caret a pending typing Mark, else the Mark the character to the left carries.
  - `activeBlockType` — the Block Node type at the Selection head.
  - `activeHeadingLevel` — the heading level there, or nil.
  - (`canUndo`/`canRedo` ship with the history slice — ps1/07 amendment.)
- **Level-aware heading rendering** (Q9.1): `BlockStyle.fontSize(for:)` now takes
  the Block Node and sizes headings by `level` (h1 32 … h5 18, h6 body) instead
  of a flat 28pt. Empty-line height and the attributed string both flow through
  the node, so layout reflects the level.

## Acceptance criteria

- [x] `isActive(.bold)` is true over a fully-bold range, false over a mixed range
- [x] At a collapsed caret, `isActive` uses a pending typing Mark, else the left
      character's Marks
- [x] `activeBlockType` / `activeHeadingLevel` report the block at the caret
- [x] h1 > h2 > h3 > h4 in rendered height (level-aware sizing)
- [x] existing layout/geometry/rendering tests stay green through the sizing change

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: `BlockStyle.fontSize(for blockType: String)` became
`fontSize(for block: Node)`; the unused `font(for marks:blockType:)` convenience
was dropped. `canUndo`/`canRedo` are intentionally deferred to the history slice
so this slice doesn't ship a stub.
