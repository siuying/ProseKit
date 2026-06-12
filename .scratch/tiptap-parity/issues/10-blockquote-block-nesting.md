# 10 — Blockquote — block-nesting pathfinder

Status: ready-for-agent

## What to build

`blockquote`, and with it the **block-nesting pathfinder** the rest of the
structural slices (lists, tasks) depend on. Today `doc` contains only flat
leaf blocks (paragraph/heading); nothing nests. A blockquote contains block
Nodes (`block+`), so this slice teaches the model and layout to nest.

### Model (ProseModel)
- `BlockquoteRule: NodeRule` — content is `block+` (paragraph/heading/blockquote…).
- `DocRule` and `BlockquoteRule` should share a "block group" notion so adding a
  block type later does not require editing each container's allowed-children
  list (the per-feature-unit spirit from slice 01).
- The **Position** model must address nesting depth: `blockInfo(containing:)`,
  `position(ofBlockAt:)`, and the block-index/offset math assume a single level
  of blocks under `doc`. Generalise to a path/depth so a Position resolves
  through nested containers.

### Layout (ProseEditor)
- A blockquote is a **container** Layout Box (these already exist) stacking its
  child boxes and drawing the quote indent bar. The leaf-only `IncrementalLayout
  Store` walk must recurse into containers while keeping per-block work O(1) for
  untouched subtrees (respect the editing-performance constraints).

### Editing
- Wrap/lift selection into/out of a blockquote (toolbar button, slice 07).

## Acceptance criteria

- [ ] blockquote validates as `block+`; nesting (blockquote in blockquote) round-trips
- [ ] Positions, selection, caret geometry, and edits are correct inside a
      nested block
- [ ] a blockquote renders as an indented container with a quote bar
- [ ] incremental relayout still validates only touched subtrees
- [ ] wrap/lift commands (headless) move a block in/out of a blockquote

## Blocked by

- 07 — Packaged toolbar (the wrap button). The model/layout nesting work does not
  depend on 07.

## Comments

2026-06-12: ready-for-agent and the highest-leverage structural slice — it
unblocks lists (14), tasks (15), and opaque-node selection (18). The bulk of the
cost is generalising the Position/block-index math from one level to arbitrary
depth; budget accordingly.
