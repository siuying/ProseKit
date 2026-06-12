# 18 — Opaque Nodes + NodeSelection (ADR 0006 phase 2)

Status: ready-for-agent

## What to build

The second phase of ADR 0006: an unknown Block Node type (e.g. `image` from
Tiptap's upload button) loads as an **Opaque Node** — rendered as a placeholder,
selected and deleted as a whole, exported byte-faithful — instead of raising the
interim load error that slices 01+ deliberately keep.

### Model
- Stop rejecting unknown node types in `Schema.validate` (the asymmetry pinned by
  `SchemaTests.testSchemaStillRejectsUnknownNodeTypes` flips here); keep the JSON
  verbatim so re-export is faithful.
- `NodeSelection` (the Selection protocol already anticipates it) to select a
  whole Opaque Node.

### Layout / interaction
- A leaf Layout Box rendering a placeholder for the opaque node; selectable as a
  unit (NodeSelection), deletable as a unit; not editable inline.

## Acceptance criteria

- [ ] an unknown block node loads (no throw) and exports byte-for-byte identical
- [ ] it renders as a placeholder box
- [ ] NodeSelection selects it as a whole; Backspace/Delete removes the whole node
- [ ] caret cannot enter it; arrow/selection steps over it
- [ ] update `SchemaTests.testSchemaStillRejectsUnknownNodeTypes` to the new
      accept-and-preserve behaviour

## Blocked by

- 10 — Blockquote / block-nesting pathfinder (NodeSelection + container layout).

## Comments

2026-06-12: ready-for-agent. This intentionally reverses the slice-01 "unknown
node still throws" boundary once NodeSelection exists; do not weaken that error
before this slice (silent stripping is never acceptable — ADR 0006).
