# Shared binding table + macOS Format menu shortcuts

Status: ready-for-agent

Context: Q9 (neutral binding table, defer Extension system), CONTEXT.md Extension.

## What to build

Lift the four hardcoded editor shortcuts (⌘B bold, ⌘I italic, Tab sink list
item, Shift+Tab lift list item) out of the iOS `keyCommands` array into a shared,
platform-neutral binding table (`(key, modifiers) → Command`) in `EditorCore`.
Each platform realizes it: iOS as `UIKeyCommand`s; macOS realizes the Cmd
shortcuts as **Format menu** key-equivalents (⌘B/⌘I, reflecting active state)
and the editing keys as `doCommand(by:)` `insertTab:`/`insertBacktab:`.

The full Extension-contributed keymap stays out of scope (the `Extension` type
is not yet built — see CONTEXT.md).

## Acceptance criteria

- [ ] The four bindings live in one shared table consumed by both platforms; no
      duplicated per-platform shortcut list.
- [ ] iOS behavior (⌘B/⌘I/Tab/Shift+Tab) is unchanged.
- [ ] macOS Format menu shows Bold ⌘B / Italic ⌘I, checked to reflect the
      caret's marks, dispatching the shared Commands.
- [ ] Tab/Shift+Tab sink/lift list items on macOS via `insertTab:`/`insertBacktab:`.
- [ ] macOS UI test: ⌘B toggles bold on the selection and Tab sinks a list
      item, asserted against the running app.

## Blocked by

- 04-mac-text-input
