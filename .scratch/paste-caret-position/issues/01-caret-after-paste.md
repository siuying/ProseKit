# Caret should move after pasted text

Status: ready-for-human

## Summary

When pasting text into `ProseView`, the caret does not end up after the
inserted text the way it does in a native `UITextView`. Surfaced while playing
with the new **UITextView Comparison** demo: paste the same text into both
panes and the native side leaves the caret after the paste, while ours appears
to leave it where it was.

## Steps to reproduce

1. Run ProseExample, open **UITextView Comparison**.
2. Copy some text to the pasteboard (e.g. select a word in either pane and Copy).
3. Place the caret in the right (Prose) pane and Paste.
4. Compare against pasting into the left (native `UITextView`) pane.

## Expected

After paste, the caret is collapsed immediately after the inserted text, ready
to keep typing — matching `UITextView`.

## Actual

The caret does not appear to advance to the end of the inserted text.

## Notes / investigation so far

The model layer looks correct: `EditorState.insertText` sets the resulting
selection to `from + text.count` (collapsed, after the text) —
`Sources/ProseEditor/EditorState.swift:22`. `ProseView.paste(_:)` routes
through `insertText`, which splits on newlines and inserts each segment —
`Sources/ProseEditor/ProseView.swift:321` and `:529`. So `state.selection`
after a paste should already be after the inserted text.

That points the suspicion at the **system caret not being notified** of the
programmatic selection change. Unlike typed text (driven by UIKit), paste
mutates the document and selection directly without bracketing the change in
`inputDelegate?.selectionWillChange(self)` / `selectionDidChange(self)` (and
`textWillChange` / `textDidChange`), so the `UITextInteraction` caret/selection
chrome can lag behind `state.selection`.

Hypotheses to confirm during triage:

- The state selection is correct but the visible system caret is stale because
  the input delegate is not told the selection moved after `paste`/`insertText`.
- Multi-segment (newline) paste interacts with `splitBlock` such that the final
  caret lands somewhere other than the end of the inserted run.

Suggested first check: log `state.selection` right after `paste(_:)` to confirm
whether this is a model bug or a system-caret-notification bug, then fix at the
right layer.

## Affected code

- `Sources/ProseEditor/ProseView.swift:529` — `paste(_:)`
- `Sources/ProseEditor/ProseView.swift:321` — `insertText(_:)`
- `Sources/ProseEditor/EditorState.swift:22` — `EditorState.insertText(_:)`

## Resolution

Confirmed it was the system-caret-notification hypothesis, not a model bug.
`paste(_:)` inserts programmatically through `insertText`, whose `performEdit`
only brackets the change in `textWillChange`/`textDidChange` — it never tells
the input delegate the selection moved. So `state.selection` advanced to the
end of the pasted run but the `UITextInteraction` caret chrome stayed put.

Fix: bracket the paste insertion in `selectionWillChange`/`selectionDidChange`
and call `refreshSelectionDisplayGeometry()`, matching `runCommand`. The model
already placed the caret correctly, so no model change was needed.

Covered by `testPasteNotifiesInputDelegateOfSelectionChange`.

## Comments
