# 14 — Bullet + ordered lists

Status: ready-for-agent

## What to build

`bulletList` / `orderedList` containing `listItem`s, each `listItem` containing
`block+` (Tiptap shapes, ADR 0003). Builds on the block-nesting pathfinder
(slice 10). Nested lists render at arbitrary depth (round-trip requires it);
nesting is created only via Tab / Shift+Tab on a hardware keyboard (slice 16) —
no indent buttons in the default toolbar (Q11).

### Model
- `BulletListRule` / `OrderedListRule` / `ListItemRule` units. `orderedList`
  carries a `start` Attr. Schema/`DocRule`/`BlockquoteRule` accept lists in the
  block group.

### Layout
- Container Layout Boxes for the list and each item; the item box draws the
  bullet / number marker in its gutter and indents its content. Arbitrary nesting
  depth.

### Editing
- Toggle a block into / out of a bullet or ordered list (toolbar dropdown, 07).
- Enter in a non-empty item splits into a new sibling item; Enter in an empty
  item lifts out one level (standard list editing).
- Tab / Shift+Tab sink/lift an item (slice 16).

## Acceptance criteria

- [ ] bullet/ordered lists + list items validate and round-trip, including nesting
- [ ] `orderedList.start` round-trips and drives the first number
- [ ] markers (bullet / ascending numbers) render in the item gutter
- [ ] toggle-list commands (headless) wrap/unwrap the selection's block
- [ ] Enter splits a non-empty item; Enter in an empty item lifts out
- [ ] nested lists render at depth

## Blocked by

- 10 — Blockquote / block-nesting pathfinder.

## Comments

2026-06-12: ready-for-agent. Depends entirely on the nesting model from 10.
Indentation is keyboard-only by design (Q11); the default toolbar ships no
indent buttons.
