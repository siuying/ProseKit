# Option-arrow should move the caret by word like UITextView

Status: ready-for-human

## Summary

In the **UITextView Comparison** demo, native `UITextView` supports hardware
keyboard word movement with Option+Left/Right. Prose currently handles arrow
keys, and Shift+Arrow selection extension, but ignores the Option modifier and
moves only one character.

## Steps to reproduce

1. Run ProseExample on an iPad simulator or iPad with a hardware keyboard.
2. Open **UITextView Comparison**.
3. Tap inside the left native `UITextView`, then press Option+Left or
   Option+Right.
4. Tap inside the right Prose pane at a comparable location, then press the
   same key combination.

## Expected

Prose moves the caret by word boundaries, matching `UITextView`.

## Actual

Prose handles the arrow direction but ignores the Option modifier, so the caret
moves one character instead of one word.

## Notes / investigation so far

The comparison demo fixture explicitly asks us to compare word-by-word caret
movement. The relevant path is `ProseView.pressesBegan(_:with:)`:

- It maps arrow key codes to `UITextLayoutDirection`.
- It passes only `key.modifierFlags.contains(.shift)` into `moveCaret`.
- `moveCaret(_:extending:)` always moves by a single geometric step via
  `position(from:in:offset: 1)`.

That covers plain arrows and Shift+Arrow, but not Option+Arrow word movement
or Option+Shift+Arrow word-selection extension.

## Affected code

- `Sources/ProseEditor/ProseView.swift:595` — hardware keyboard press handling
- `Sources/ProseEditor/ProseView.swift:615` — single-step caret movement
- `Sources/ProseEditor/ProseView+UITextInput.swift:84` — character-offset
  position movement that could support word/token movement with tokenizer logic

## Resolution

`pressesBegan` now checks `key.modifierFlags.contains(.alternate)` on the
horizontal arrows and routes to a new `moveCaretByWord(_:extending:)`, which
reuses the system `UITextInputStringTokenizer` (the same one driving
double-tap word select). The tokenizer reports a boundary at *every* word edge
(start and end), so a single hop stops on the near edge of the inter-word gap;
`wordTarget(from:direction:)` walks boundaries until it reaches the far edge —
the next word *end* going right, the previous word *start* going left — which
matches UITextView. Option+Shift+Arrow keeps the anchor and extends the head
the same way. The vertical arrows ignore the modifier (it is meaningless
there) and stay single-step.

A surprising tokenizer detail confirmed on the simulator: a word end answers
`isPosition(_:atBoundary:.word, inDirection:.storage(.forward))` and a word
start answers `.backward`, so the stop edge equals the travel direction.

Covered by `testOptionArrowMovesCaretByWord` and
`testOptionShiftArrowExtendsSelectionByWord`.

## Comments
