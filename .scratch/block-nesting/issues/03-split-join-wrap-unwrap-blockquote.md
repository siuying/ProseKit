# 03 — Split/join inside a blockquote; wrap & unwrap

Status: ready-for-agent

## What to build

The structural editing that makes a blockquote feel native, completing
blockquote (tiptap-parity issue 10). Split/join now happen *within* a container,
and two new container operations — wrap and unwrap (lift) — let content enter and
leave the quote.

End-to-end behavior:

- **Enter** in a quoted paragraph splits it into a sibling quoted paragraph
  (the split happens inside the blockquote, not at the top level).
- **Backspace** at the start of a non-first quoted block joins it into the
  previous quoted sibling.
- **Backspace** at the start of the blockquote's *first* block **lifts** that
  block out of the quote (unwrap-at-edge), the rest of the quote staying intact;
  Backspace in an empty sole-quoted block removes the quote.
- The `> ` **Input Rule** at the start of a paragraph **wraps** it into a
  blockquote.
- **Enter** on an empty trailing quoted paragraph exits the quote (lifts a new
  empty paragraph after it) rather than adding another empty quoted line.

New structural Steps — `WrapInStep` / `LiftStep` (or equivalents) — carry their
own `apply` / `inverted` / `map`, co-located with the existing structural Steps,
and build on the path-addressed primitive. Split/join Steps generalize to operate
within the addressed container.

## Acceptance criteria

- [ ] Enter splits a quoted paragraph into a sibling within the same blockquote;
      caret lands in the new block
- [ ] Backspace joins a non-first quoted block into its previous sibling
      (runs/Marks preserved across the join)
- [ ] Backspace at the blockquote's first block lifts it out; the remaining
      quoted blocks are unchanged
- [ ] `> ` wraps the current paragraph into a blockquote; Backspace immediately
      after reverts it (Input Rule revert contract)
- [ ] Wrap and lift are invertible (round-trip restores the original Document,
      index included) and map Positions correctly
- [ ] Rendering-equivalence across split / join / wrap / unwrap
- [ ] Full package suite green

## Blocked by

- `block-nesting/issues/02` (path-addressed editing primitive).
