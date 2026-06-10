# 04 — Multi-block structural editing

Status: done

## What to build

Editing that changes document *structure*, not just text, across multiple stacked
blocks. Three behaviors:

- **Enter splits the current block** into two blocks of the same type at the
  caret (paragraph → two paragraphs; heading → heading + heading, or per the
  decided rule).
- **Backspace at the start of a block joins** it into the previous block (merging
  their inline content), or removes empty blocks.
- **A command toggles the current block** between `paragraph` and
  `heading(level)`.

These are `Command`s operating on the Document tree and producing `ReplaceStep`s
(structural replacements over Positions), never raw `\n` text mutations — Enter is
a `splitBlock`, not "insert newline". The layout already stacks multiple Layout
Boxes vertically (from 01); this slice exercises boxes appearing, disappearing,
and changing type, with incremental invalidation marking only affected boxes
dirty.

Commands are wired to a keymap (hardware Enter / Backspace) and are also callable
programmatically (a debug control may trigger the heading toggle).

## Acceptance criteria

- [ ] Enter at a caret splits the block into two blocks of the correct type; caret lands at the start of the new block
- [ ] Backspace at block-start joins into the previous block, merging inline content; caret lands at the join point
- [ ] Backspace in an empty block removes it and moves the caret to the previous block
- [ ] A command toggles the caret's block between paragraph and heading(level) and back, preserving inline content
- [ ] These are structural Steps (no literal newline characters appear in any text Node) — assertable on the resulting Document/JSON
- [ ] Layout updates correctly as boxes are added/removed/retyped; unaffected boxes are not re-typeset

## Blocked by

- 02 — Type into a paragraph
