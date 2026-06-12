# 04 — Mark exclusion rules + superscript/subscript

Status: done

## What to build

Mark coexistence rules (a model concern) plus two Marks that need them:

- A per-Mark `MarkRule` unit (ProseModel, mirroring `NodeRule`) declaring what a
  Mark excludes. `MarkRules.adding(_:to:)` is ProseMirror `addToSet`: adding a
  Mark drops the Marks it excludes; a Mark an existing Mark excludes is rejected.
- Retrofit **code excludes all** (Q9.4): adding `code` clears a run's other
  Marks; other Marks can't join a code run.
- **superscript / subscript** Marks, mutually exclusive (Q9.5), rendered via
  `kCTSuperscriptAttributeName` (+1 / -1).

Both the document mark-add seam (`Document.settingMark`) and the typing-mark set
(`EditorState.toggleTypingMark`) route through `MarkRules.adding`.

## Acceptance criteria

- [x] `MarkRules.adding(code, to:[bold,italic])` → `[code]`
- [x] `MarkRules.adding(bold, to:[code])` → `[code]` (rejected)
- [x] superscript and subscript are mutually exclusive both directions
- [x] unrelated Marks coexist; adding a present Mark is idempotent
- [x] `Document.addingMark(code)` over a bold run yields code-only
- [x] superscript and subscript each render distinctly from plain and each other
- [x] `superscript`/`subscript` in `Schema.slice1.marks`; one `MarkRule` unit per
      excluding Mark (`CodeRule`, `SuperscriptRule`, `SubscriptRule`)

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: Exclusion lives in ProseModel (`Schema/MarkRule.swift`), the
structural authority; `MarkRules.adding` is public so `EditorState`'s typing-mark
set uses the same rule as document edits. Rendering uses the CoreText superscript
attribute rather than a manual baseline shift.
