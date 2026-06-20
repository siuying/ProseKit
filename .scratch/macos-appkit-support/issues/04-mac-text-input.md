# macOS text input: type and delete via NSTextInputClient

Status: ready-for-agent

Context: ADR 0008, Q5 (NSTextInputClient + doCommand routing).

## What to build

Make the macOS `ProseView` conform to `NSTextInputClient` so typed characters
insert and delete through the shared `EditorCore` Commands. `keyDown` flows
through `interpretKeyEvents(_:)`; printable input arrives as
`insertText(_:replacementRange:)` and the basic editing keys
(`deleteBackward:`, `insertNewline:`) arrive via `doCommand(by:)`, each mapped to
the corresponding Command. Cover marked-text basics (`setMarkedText`,
`unmarkText`, `hasMarkedText`) enough for dead keys / basic IME composition.

The caret advances and the document relayouts after each edit; the Selection
Layer reflects the new collapsed selection.

## Acceptance criteria

- [ ] Typing inserts text and advances the caret in the Mac editor.
- [ ] Backspace deletes; Return splits the block (via existing Commands).
- [ ] Dead-key / basic IME composition shows marked text and commits correctly.
- [ ] Edits route through `EditorCore` Commands — no Mac-only editing algebra.
- [ ] Undo/redo of these edits works through the Step-based **History**.
- [ ] macOS UI test: typing into the editor inserts text and backspace deletes
      it, asserted against the rendered document.

## Blocked by

- 03-mac-caret
