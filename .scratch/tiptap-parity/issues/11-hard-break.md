# 11 — hardBreak (+ Shift+Enter)

Status: ready-for-agent

## What to build

`hardBreak`, the first inline **leaf** Node (Q: hardBreak is in the supported
set). It is an inline node with no text that forces a line break within a block
(Shift+Enter), without ending the block.

This is the first non-text inline node, so it breaks the slice-1 assumption that
a block's content is a flat run of text Nodes. The position model and the
text-range helpers (`textRange`, `blockTextStart`, `settingMark`, the
text-offset math in `Document`) assume text-only block content and must learn to
step over a 1-wide inline leaf.

### Model
- Schema: `hardBreak` accepted as inline content of paragraph/heading; it carries
  no Marks and no text. `nodeSize == 1` (an inline leaf is one Position) — note
  `Node.nodeSize` currently returns 2 for an empty non-text node; fix for inline
  leaves.
- The text-range/offset helpers must treat a hardBreak as one Position that is
  not text.

### Layout
- A hardBreak forces a new Line Fragment within the same leaf Layout Box (shared
  newline-handling groundwork with codeBlock, slice 12).

### Editing
- Shift+Enter inserts a hardBreak at the caret.

## Acceptance criteria

- [ ] hardBreak validates as inline content; carries no text/marks; `nodeSize==1`
- [ ] positions, selection, and mark ranges remain correct across a hardBreak
- [ ] a hardBreak forces a line break within the block when rendered
- [ ] Shift+Enter inserts a hardBreak
- [ ] a document with a hardBreak round-trips verbatim

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: ready-for-agent. This is a position-model slice, not a cosmetic one —
the main cost is teaching `Document`'s text helpers about a non-text inline leaf.
Shares newline-in-a-block layout work with codeBlock (12).
