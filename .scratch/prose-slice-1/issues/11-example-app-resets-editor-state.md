# 11 — Example app wipes editor state on every SwiftUI update

Status: done

## Problem

`ProseDocumentView.updateUIView` (`Example/ProseExample/ProseExampleApp.swift`)
assigns `uiView.document = Self.document` on every SwiftUI update cycle. The
`ProseView.document` setter rebuilds `EditorState` from scratch, so any SwiftUI
re-render (trait change, rotation, keyboard appearance, …) silently reverts all
edits to the static sample document and resets the selection to the document
end. While testing, this compounds the impression that selection and editing
are broken.

## What to build

- Set the document once at `makeUIView` time; `updateUIView` must not reassign
  an unchanged document (guard on identity/equality, or drop the assignment
  entirely while the sample document is static).
- Consider whether `ProseView.document`'s setter should preserve a still-valid
  selection instead of resetting to the document end — decide and document.

## Acceptance criteria

- [ ] Typing, then triggering a SwiftUI update (e.g. rotate the simulator), keeps the edited document and selection
- [ ] Example app still renders the sample document on first launch

## Blocked by

- 02 — Type into a paragraph

## Comments

2026-06-10: Fixed — `updateUIView` no longer reassigns the document; the sample
document is set once in `makeUIView`. Decision on the `ProseView.document`
setter: kept as a full state reset. It is a whole-document replacement API;
preserving selection across an arbitrary document swap has no well-defined
answer until remote Transactions exist (collaboration is designed-for, not
built). Callers that want edit-preserving updates should dispatch Transactions.
