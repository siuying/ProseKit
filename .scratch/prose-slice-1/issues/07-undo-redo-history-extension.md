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
