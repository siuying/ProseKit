# 12 — codeBlock

Status: ready-for-agent

## What to build

A `codeBlock` Block Node (Q9.3): one plain-text run with literal `\n`, **no
Marks inside**, a `language` Attr preserved with no UI. It is a leaf block (no
nesting), so it does not depend on the block-nesting pathfinder (slice 10) — but
it is the first block whose text contains hard newlines, which the current
layout does not handle.

### Model (ProseModel)
- `CodeBlockRule: NodeRule` — content is text only and carries no Marks (enforce
  marks-empty here, unlike paragraph). `language` Attr preserved verbatim.
- `DocRule` must accept `codeBlock` as a child.
- Add `codeBlock` to `Schema.slice1.nodes`.

### Layout (ProseEditor) — the real work
- `typesetLineFragments` currently wraps by width only; a codeBlock must **hard-
  break at `\n`**. Split the block's text on `\n` and typeset each segment, so an
  empty line still yields a Line Fragment of one line height.
- Render monospace (already available via the `code` run path / `RunStyle`) and a
  code-block background fill (a manual Canvas pass like highlight).

### Editing (ProseEditor)
- Enter inside a codeBlock inserts a literal `\n` (not `splitBlock`).
- Enter on an empty trailing line exits the codeBlock into a following paragraph
  (deliberate touch adaptation — there is no other way to leave it on a phone).

## Acceptance criteria

- [ ] codeBlock validates with text + no marks; marks inside are rejected
- [ ] `language` Attr round-trips verbatim; no UI sets it
- [ ] a codeBlock renders one monospace run with hard line breaks at `\n`
- [ ] a code-block background is drawn behind the block
- [ ] Enter inserts `\n`; Enter on an empty trailing line exits to a paragraph
- [ ] `CodeBlockRule` is one unit; `DocRule`/schema updated

## Blocked by

- 07 — Packaged toolbar (entry point). Model/layout do not depend on 07; only the
  toolbar button does.

## Comments

2026-06-12: Filed as ready-for-agent. The newline-aware layout is the crux and is
shared groundwork with hardBreak (slice 11) — consider doing 11 and 12 together,
since both introduce hard line breaks into a single block's typesetting.
