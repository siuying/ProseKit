# 02 — Type into a paragraph

Status: done

## What to build

First interactive slice: a user taps the editor, the keyboard appears, and they
can type and delete characters in a single paragraph with a blinking caret. This
slice also brings up the load-bearing edit substrate that everything later rests
on.

`ProseModel`: `Step` (start with `ReplaceStep`), `Transaction` (an ordered batch
of Steps plus the resulting Selection), an `Origin` tag on every Transaction
(local / remote / history), and `Mapping` (remap a `Position` across Steps). Steps
must both **apply** and **invert**. This is the substrate slice — test it hard.

`ProseEditor`: the content view conforms to the core of `UITextInput` —
`insertText`, `deleteBackward`, `text(in:)`, `replace(_:withText:)`, plus the
caret rect so a caret can be drawn and blink. A native character change is
translated into a `ReplaceStep`, dispatched as a local-origin `Transaction`; the
new Document drives relayout. Relayout is incremental: each Step reports its
changed Position range, and via `Mapping` only the Layout Boxes that range
intersects are marked dirty and re-typeset; others keep their cached result.

Scope is a single paragraph — block splitting/joining is slice 04, selection
geometry beyond the caret is slice 03, IME is slice 08.

## Acceptance criteria

- [ ] `ReplaceStep` applies and inverts; `apply(invert(apply(s)))` round-trips the document (unit-tested)
- [ ] `Mapping` remaps positions across a `ReplaceStep` correctly for positions before/inside/after the changed range (unit-tested)
- [ ] Every `Transaction` carries an `Origin`; the dispatch path tags typed edits as local
- [ ] Typing and deleting in the example app mutates the Document via Transactions and updates the rendered text
- [ ] A caret renders at the insertion point and blinks; it stays correct after inserts and deletes
- [ ] Only Boxes intersecting the changed range are re-typeset on each keystroke (assertable: untouched boxes keep their cached typeset result)

## Blocked by

- 01 — Walking skeleton: render a static Document
