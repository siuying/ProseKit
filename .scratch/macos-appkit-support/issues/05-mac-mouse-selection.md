# macOS mouse selection: drag, word/line click, and highlight rendering

Status: ready-for-agent

Context: Q8 (Selection Layer pure renderer, key-window convention).

## What to build

Mouse-driven range selection on macOS. `mouseDown`/`mouseDragged`/`mouseUp` on
the view shell create and extend a **TextSelection** by translating points
through the shared `GeometryMapper`; double-click selects a word and triple-click
selects the line/paragraph. The **Selection Layer** draws the range highlight
behind the text (reading `selectionRects` from the core).

Honor the key-window convention: the highlight is accent-colored when the
window is key and gray when it is not.

## Acceptance criteria

- [ ] Click-drag selects a range; the highlight tracks the drag live.
- [ ] Double-click selects a word; triple-click selects the line/paragraph.
- [ ] Highlight is accent-colored in the key window, gray when the window
      resigns key.
- [ ] Selection geometry comes from the shared `GeometryMapper`
      (`selectionRects`), not a Mac-only computation.
- [ ] The Canvas draws no highlight; only the Selection Layer does.
- [ ] macOS UI test: click-drag selects a range and double-click selects a
      word, asserted via the app's accessibility/selection state.

## Blocked by

- 03-mac-caret
