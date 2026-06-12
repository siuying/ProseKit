# 07 — Undo / redo (history Extension)

Status: ready-for-agent

## What to build

Undo and redo, authored as an `Extension` (dogfooding the extension API). The
history keeps a stack of inverted Steps grouped by Transaction (with light
time/transaction grouping), and **skips non-local Origins** so a future
collaborator's edit is never swept into a local undo.

Undo pops the most recent local Transaction, applies its inverse as a new
Transaction tagged with a `history` Origin, and restores the prior Selection;
redo replays it. Wired to `⌘Z` / `⌘⇧Z` and the shake gesture; the native
`UndoManager` and shake-to-undo are disabled so this path is authoritative.

This slice is also the sharpest correctness probe for the Step/Mapping substrate
from 02/05 — if inversion or mapping is wrong, undo reveals it.

## Acceptance criteria

- [ ] ⌘Z undoes the last edit (text insert/delete, block split/join, heading toggle, mark toggle); ⌘⇧Z redoes it
- [ ] Undo/redo restore the Selection that was active around the edit
- [ ] History Transactions are tagged with a `history` Origin and are not themselves pushed onto the undo stack as new undoable edits
- [ ] Transactions with a non-local Origin are not added to the local undo stack
- [ ] The native UndoManager and shake-to-undo are disabled; the Extension is the only undo path
- [ ] A sequence of mixed edits undone fully returns the Document to its exact starting JSON (unit/integration-tested)

## Blocked by

- 05 — Inline marks: bold / italic / code

## Comments

2026-06-12 (tiptap-parity): Amended per ADR 0004. Two corrections to the body
above:

1. **Not an Extension.** There is no public Extension API yet (Q2c, ps1/06 is
   untouched). Author history as a per-feature internal unit alongside the others,
   like the Mark/Node units added in tiptap-parity slice 01 — not via the
   Extension surface.
2. **Bridge NSUndoManager, don't "disable" it.** ADR 0004: keep our Step-based
   stack authoritative, but route the system gestures (shake, ⌘Z, the keyboard
   undo bar) *into* our stack via NSUndoManager rather than turning it off.
   Coalesce consecutive typing into one entry, broken by a ~500ms pause or a
   selection jump; bound the stack (~100 entries).

**Prerequisite discovered during slices 02–06:** the command layer currently
bypasses Steps — `toggleMark`, `toggleHeading`, `setTextAlign`, `setLink`,
`splitBlock`, `joinBackward`, and the input-rule transform all compute a new
Document and call `EditorState.replaceDocument`, so only plain text insert/delete
produce `ReplaceStep`s through `Transaction`. A faithful Step-based,
Mapping-rebasable history (ADR 0004) needs those commands to emit invertible
Steps first. Do **not** substitute a Document-snapshot stack — it cannot rebase
through Mapping and so dead-ends the collaboration story ADR 0004 exists to keep
open. Treat "commands emit Steps" as the first task of this slice.

