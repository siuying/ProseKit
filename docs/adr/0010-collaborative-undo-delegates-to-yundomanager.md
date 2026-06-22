---
status: accepted
---

# Collaborative undo delegates to YUndoManager

When collaboration is active, undo/redo is delegated to Yrs `YUndoManager` scoped
to the local origin, not the step-based history stack of [ADR 0004]. Collaborative
undo must revert only the local peer's changes as a *new* CRDT operation so
concurrent remote edits survive — the merge cases this raises (undoing a mark over
text a peer partially deleted, undoing into a region a peer restructured) are
exactly what `YUndoManager` was built for, and it is what the y-prosemirror
reference uses. ADR 0004's step+`Mapping` history remains the authority for the
solo (non-collaborative) editor; this decision only qualifies it for collab.

## Considered Options

- **Keep the step-based stack, made collab-aware** — carry undo entries forward
  through remote-origin `Mapping` and redispatch inverted Steps. One history
  system, honors ADR 0004, but hand-rolls collaborative-undo correctness for the
  hard merge cases. Rejected: the risk lives in precisely the cases `YUndoManager`
  already solves.
- **Delegate to `YUndoManager` in collab mode** (chosen).

## Consequences

- Two undo code paths: step-based when solo, Y-driven when collaborating. They
  must present one face to the user (same gesture/menu wiring).
- While collaborating the solo step history is **dormant**: it neither serves
  undo nor *records* local edits (`EditorState.recordsHistory == false`).
  Recording would accumulate steps whose positions concurrent remote ops
  invalidate (remote edits apply without history mapping), so re-enabling the
  solo stack on `detach()` would otherwise expose stale, replay-unsafe entries.
  Detach therefore leaves an empty solo history; fresh solo edits record anew.
- A `YUndoManager` undo surfaces as a `history`/`remote`-Origin **Transaction** via
  the **Binding**, not as a replayed local Step entry.
- The `NSUndoManager` bridge (system shake / Cmd+Z / keyboard undo bar) routes into
  whichever stack is active for the current mode.
- Typing-coalescing groups (~500ms / selection-jump breaks from ADR 0004) must be
  reconciled with `YUndoManager`'s capture-stop grouping in collab mode.

[ADR 0004]: 0004-step-based-history-not-nsundomanager.md
