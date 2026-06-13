# 06 — Task lists

Status: ready-for-agent

## What to build

Task lists — checkable list items — covering tiptap-parity issue 15. Reuses the
list-item machinery from slice 04; what's new is per-item state (the `checked`
attr) and a checkbox decoration the user can toggle.

End-to-end behavior:

- The Schema accepts `taskList` (container of `taskItem`) and `taskItem`, the
  latter carrying Tiptap's boolean `checked` attr.
- A `taskItem` container box draws a **checkbox** (checked/unchecked) instead of
  a bullet; checked items may render with the Tiptap-standard styling.
- Tapping the checkbox dispatches a **Command** that toggles the item's `checked`
  attr (a block-attr Step, like `SetTextAlign`), leaving Positions stable.
- Enter / Backspace / Tab behave as in slice 04/05 (a task item is a list item
  with extra state); the `checked` attr survives split/join/sink/lift.

## Acceptance criteria

- [ ] A Tiptap `taskList` loads, round-trips (incl. `checked`), and renders with
      checkboxes
- [ ] Tapping a checkbox toggles `checked` via a Command + block-attr Step;
      undo/redo restores it; Positions stay stable
- [ ] Splitting a checked item yields a new item with the intended `checked`
      state; join/sink/lift preserve `checked`
- [ ] Enter/Backspace/Tab behave as for bullet items
- [ ] Rendering-equivalence for toggle; iOS simulator screenshot confirms
      checkbox states
- [ ] Full package suite green

## Blocked by

- `block-nesting/issues/04` (list-item container machinery). Independent of 05.
