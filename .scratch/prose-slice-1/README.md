# Prose — Slice 1

The first vertical slice of the **Prose** editor: a native iOS rich-text editor
built on a custom CoreText layout engine over a ProseMirror-style document model.
See `CONTEXT.md` (glossary) and `CONTEXT-MAP.md` at the repo root.

## Scope

- Package `Prose` = `ProseModel` (pure model) + `ProseEditor` (CoreText view +
  `UITextInput`), plus an Xcode example app in `Example/`.
- Nodes: `doc`, `paragraph`, `heading(level)`. Marks: `bold`, `italic`, `code`.
- PM-faithful model: immutable Node tree, integer Positions, Steps, Mapping,
  origin-tagged Transactions; `Document ↔ JSON`.
- Collaboration designed-for, not built. Undo via a history Extension.

## Issues & dependency order

```
01 walking skeleton (render static doc)        ← start here
└─ 02 type into a paragraph                     (brings up Steps/Mapping substrate)
   ├─ 03 caret placement & range selection
   ├─ 04 multi-block structural editing ┐
   ├─ 05 inline marks (bold/italic/code)┘─ 06 harden Extension API (HITL)
   │                                    └─ 07 undo/redo (history Extension)
   └─ 08 single-user IME (marked text)
```

04, 05, 08 can proceed in parallel once 02 lands. 06 is HITL (Extension public
API review); everything else is AFK.
