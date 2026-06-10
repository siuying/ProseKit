# 08 — Single-user IME (marked text)

Status: ready-for-agent

## What to build

CJK / emoji composition via the `UITextInput` marked-text path. While composing,
the in-progress (marked) text is shown — conventionally underlined — and is
committed to the Document only when composition finalizes.

`ProseEditor`: implement `setMarkedText(_:selectedRange:)`, `unmarkText()`,
`markedTextRange`, and the marked-text styling. A composition buffer holds the
marked run; intermediate composition states are **not** pushed as committed
Transactions — only the finalized committed run becomes a local-origin
`ReplaceStep`/`Transaction`. The caret/selection behaves correctly within the
marked range during composition.

This is the *single-user* case only: there is no remote delta to reconcile against
an active composition (collaboration is designed-for but not built), which keeps
this tractable. The marked range is rendered distinctly from committed text.

## Acceptance criteria

- [ ] Typing Pinyin/Zhuyin/Kana shows marked (composing) text, visually distinct (underlined), before commit
- [ ] Selecting a candidate commits the finalized text as a single local-origin Transaction
- [ ] Intermediate composition states do not create committed Transactions (assertable: the undo stack gains one entry per committed run, not per keystroke)
- [ ] `markedTextRange` is reported correctly during composition and cleared on `unmarkText`
- [ ] Caret and deletion behave correctly inside an active composition
- [ ] Emoji composition (e.g. multi-scalar emoji) commits as a single run

## Blocked by

- 02 — Type into a paragraph
