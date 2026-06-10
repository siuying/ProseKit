# 12 — Rich copy/paste via Document Slices

Status: needs-triage

## What to build

Upgrade cut/copy/paste from plain text to structure- and mark-preserving, using
a first-class **Slice** concept (ProseMirror-style).

`ProseModel`: a `Slice` type — a contiguous fragment of a Document cut between
two Positions, carrying its content plus open start/end depths, so it can be
fitted into another place in a Document. Serializable (JSON, same scheme as
`Document ↔ JSON`). The paste path needs the *fitting* algorithm: inserting a
Slice at a Position must produce a Schema-valid Document (e.g. pasting half a
heading into a paragraph, or multiple blocks into the middle of a block).

`ProseEditor`: `copy:`/`cut:` write both a serialized Slice (custom UTType) and
a plain-text fallback to `UIPasteboard`; `paste:` prefers the Slice
representation when present and falls back to plain text (newlines split
blocks, matching issue 13's behavior).

## Why deferred

Decided during the system-selection grilling (2026-06-10): edit-menu actions
land first with plain-text fidelity only, because Slice + fitting is real model
work and shouldn't ride along in a UI-adoption change. This ticket exists so
rich fidelity isn't forgotten.

## Acceptance criteria

- [ ] Copying a bold/italic/code run and pasting it preserves the Marks
- [ ] Copying across a block boundary and pasting reproduces the block structure (Schema-valid result)
- [ ] Pasting a Slice whose ends are open mid-block joins text into the surrounding blocks rather than forcing new blocks
- [ ] Copying in Prose and pasting into another app yields sensible plain text
- [ ] Pasting plain text from another app still works (newlines split blocks)
- [ ] Slice survives a JSON round-trip

## Blocked by

- 13 — System selection UX via UITextInteraction (plain-text edit menu lands there)
