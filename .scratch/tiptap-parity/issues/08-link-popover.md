# 08 — Link popover

Status: ready-for-agent

## What to build

The link UX on top of the `link` Mark (slice 05) and toolbar (slice 07), per Q6:

- Toolbar link button opens a popover with a URL field.
- Button disabled on a collapsed caret with no selection.
- Caret inside a link → button active, popover pre-filled with the href, offering
  Remove / Open.
- Tapping a link while editable only places the caret (no navigation).
- (Paste-URL-onto-selection already shipped in slice 05.)

Needs a type-based "caret in link" query (the slice-06 `isActive` is value-based;
add `linkHref(at:)`/`activeLink` returning the href under the caret regardless of
its other attrs).

## Acceptance criteria

- [ ] link button disabled when the selection is an empty caret outside a link
- [ ] selecting text + entering a URL applies a link (reuses `Commands.setLink`)
- [ ] caret inside a link → button active, popover pre-filled, Remove clears the
      whole link, Open opens the URL
- [ ] tapping a link in editable mode places the caret only
- [ ] `activeLink`/`linkHref(at:)` reports the caret's link href

## Blocked by

- 05 — Link mark + paste-URL.
- 07 — Packaged toolbar.

## Comments

2026-06-12: ready-for-agent. Popover + gesture UX needs app verification; the
`activeLink` query and Remove/Open commands are unit-testable and should be
test-first.
