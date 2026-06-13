# 04 — Bullet list: render markers + item editing

Status: ready-for-human

## What to build

Single-level bullet lists, end to end, reusing the container machinery proven by
blockquote. Covers the bullet half of tiptap-parity issue 14.

End-to-end behavior:

- The Schema accepts `bulletList` (container of `listItem`) and `listItem`
  (container of Block Nodes — at least a paragraph).
- The container Layout Box for a `listItem` draws a **bullet marker** in its
  frame (the Canvas decoration walk from slice 01); list content is indented.
- **Enter** at the end of a list item creates a new sibling list item with the
  caret in it.
- **Enter** on an empty list item lifts out of the list (exits to a paragraph) —
  the standard "double-enter ends the list" behavior.
- **Backspace** at the start of a list item's first block joins into the previous
  item, or lifts the item out of the list when it is the first item.
- The `- ` / `* ` **Input Rule** wraps a paragraph into a one-item bullet list;
  Backspace immediately after reverts.

Built on the wrap/lift/split/join Steps from slice 03 (a list item is just
another container); only marker rendering and the list-specific Enter/Backspace
intents are new.

## Acceptance criteria

- [x] A Tiptap `bulletList` loads, round-trips, and renders with bullets +
      indent
- [x] Enter creates a new list item; Enter on an empty item exits the list
- [x] Backspace joins into the previous item / lifts the first item out
- [x] `- ` (and `* `) wraps a paragraph into a bullet list; Backspace reverts
      (rule + revert unit-tested via `InputRules.apply`; live keystroke wiring
      stays deferred project-wide, as for the heading / `> ` rules)
- [x] Structural Steps invert and map correctly (round-trip restores Document +
      index)
- [x] Rendering-equivalence across item create / join / lift; iOS simulator
      screenshot confirms bullets render
- [x] Full package suite green

## Blocked by

- `block-nesting/issues/03` (wrap/lift/split/join container Steps).
