# 17 — Input rule engine + StarterKit rules

Status: done (engine + heading rules); list/blockquote/code/task rules and live
wiring deferred

## What to build

The Input Rule substrate (CONTEXT glossary) and the markdown block shortcuts
(Q5). An `InputRule` has a `trigger` and a transform; `InputRules.apply` fires
the first rule whose trigger is the whole block text up to a collapsed caret
(i.e. typed at block start).

Shipped now: `#`…`######` + space → heading of that level (reuses the existing
`togglingHeading` structural edit after consuming the trigger).

Deferred:
- `- ` / `1. ` / `[ ] ` / `> ` / ```` ``` ```` rules — land with their node types
  (slices 14, 15, 10, 12).
- Live wiring (run rules after each `insertText`) and **backspace immediately
  after a match reverts to literal text** — editor integration, a later slice.

## Acceptance criteria

- [x] `# ` at block start → heading level 1, trigger text consumed
- [x] `### ` → level 3; `###### ` → level 6
- [x] non-trigger text (`#x `) and a trigger not at block start (`a# `) do nothing
- [ ] list/blockquote/code/task rules — deferred to their node-type slices
- [ ] live keystroke wiring + backspace-revert — deferred

## Blocked by

- 01 — Per-feature format units. (List rules additionally need 14; the engine
  does not.)

## Comments

2026-06-12: Engine matches a literal block-start trigger rather than a regex —
sufficient for the markdown block prefixes and clearer to test. The heading
transform consumes the trigger via `replacingText` then promotes the paragraph
with `togglingHeading`.
