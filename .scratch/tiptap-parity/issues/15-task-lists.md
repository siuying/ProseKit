# 15 — Task lists

Status: ready-for-agent

## What to build

`taskList` containing `taskItem`s, each with a boolean `checked` Attr and
`block+` content (Tiptap shapes). Builds on lists (slice 14).

### Model
- `TaskListRule` / `TaskItemRule` units; `taskItem.checked` Attr (bool), accepted
  present or absent. No auto-strikethrough on checked content (Q8).

### Layout / interaction
- Each item renders a tappable checkbox in its gutter plus its content.
- Tapping the checkbox toggles `checked` **without moving the caret or popping
  the keyboard** (Q8). The toggle is a Transaction (undoable) and must **not
  coalesce with typing** (its own history entry).

## Acceptance criteria

- [ ] taskList/taskItem validate and round-trip; `checked` round-trips
- [ ] a checkbox renders per item, reflecting `checked`
- [ ] tapping the checkbox toggles `checked` without changing selection or
      first-responder/keyboard state
- [ ] the toggle is an undoable Transaction that does not coalesce with typing
- [ ] checked items are NOT auto-struck-through

## Blocked by

- 14 — Bullet + ordered lists.

## Comments

2026-06-12: ready-for-agent. The interaction constraints (no caret move, no
keyboard pop, no history coalescing) are the subtle part and depend on the
history slice for the coalescing guarantee.
