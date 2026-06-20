# macOS caret motion and deletion via doCommand selectors

Status: ready-for-agent

Context: Q5 (doCommand(by:) → Command mapping).

## What to build

Map AppKit's standard motion/deletion selectors to the **Command** layer so the
Mac editor honors system key bindings (including `DefaultKeyBinding.dict` and
Emacs-style chords) without hand-parsing `keyDown`. Cover at least:
`moveLeft:`/`moveRight:`, `moveWordLeft:`/`moveWordRight:`,
`moveToBeginningOfLine:`/`moveToEndOfLine:`,
`moveToBeginningOfParagraph:`/`moveToEndOfParagraph:`, their `...AndModifySelection`
variants, and `deleteWordBackward:`/`deleteWordForward:`. Each resolves to the
existing Command vocabulary; motion that extends selection keeps the anchor and
moves the head.

## Acceptance criteria

- [ ] Arrow keys move the caret; Shift+Arrow extends the selection.
- [ ] Option+Arrow moves by word; Cmd+Arrow moves to line/paragraph edges.
- [ ] `deleteWordBackward:`/`deleteWordForward:` delete by word.
- [ ] Bindings come from AppKit's resolved selectors, not raw `keyCode` parsing.
- [ ] Motion commands reuse the same `EditorCore`/`GeometryMapper` queries used
      elsewhere.
- [ ] macOS UI test: arrow and Option+Arrow move the caret by char/word, and
      Shift variants extend the selection, asserted against the running app.

## Blocked by

- 04-mac-text-input
