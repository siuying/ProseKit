---
status: accepted
---

# YDoc is the convergence authority (collaboration inverts the projection rule)

When collaboration is active, a shared Yjs document (`YDoc`) becomes the authority
every peer converges on: all edits — local and remote — flow into it, and on
divergence it reconciles into the editor's **Document** via a `remote`-**Origin**
**Transaction**. This deliberately qualifies the core invariant in CONTEXT.md
("the document tree is the authority… never the other way around"): the Document
remains the authority the *layout* projects from, but across peers the CRDT replica
is the *convergence* authority. We accept that a remote edit can override a local
one mid-keystroke, because CRDT merge is the only mechanism that actually
guarantees convergence across peers — and ProseKit's `Origin`/`Mapping` seam was
built precisely to keep this inversion tractable.

## Considered Options

- **Keep `Document` as the sole authority, treat the `YDoc` as a synced mirror** —
  preserves the glossary verbatim, but forces us to hand-build convergence
  guarantees that a CRDT already owns. Rejected: this is where homegrown
  collaborative editors break.
- **Make the `YDoc` the convergence authority** (chosen) — matches y-prosemirror,
  where the shared document is canonical and the editor doc is a reconciled
  projection.

## Consequences

- Remote-origin transactions are non-undoable, are never re-pushed to the replica,
  and are always accepted.
- The "never the other way around" layout invariant now carries an explicit
  collab-mode asterisk (see **Convergence Authority** in CONTEXT.md).
- A `Document` passed to the editor is discarded when joining a populated replica
  (see the **Join** rule).
