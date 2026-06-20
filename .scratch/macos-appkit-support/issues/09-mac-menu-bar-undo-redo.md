# macOS menu bar: Edit menu wired to commands and Step-based History

Status: ready-for-agent

Context: Q10 (menu surface, library/Example boundary), ADR 0004 (History not NSUndoManager).

## What to build

Round out the Mac menu bar in the Example app. The `ProseEditor` library exposes
the Command vocabulary, the can-perform queries, and undo/redo on the Step-based
**History**; the Example app owns the actual `NSMenu`/SwiftUI `.commands`
wiring. Build the **Edit** menu (Undo, Redo, Cut, Copy, Paste, Select All) and
fold the Format menu from slice 08 into the menu bar.

Critically, bind Undo/Redo to the editor's **History** — never `NSUndoManager`,
even though AppKit's responder chain reaches for it by default (ADR 0004).

## Acceptance criteria

- [ ] Edit menu (Undo/Redo/Cut/Copy/Paste/Select All) appears and is enabled
      per the core can-perform queries.
- [ ] Undo/Redo (⌘Z / ⇧⌘Z) drive the Step-based **History**, not `NSUndoManager`.
- [ ] Menu-bar Cut/Copy/Paste share the same path as the contextual menu.
- [ ] Menu-bar wiring lives in the Example app; the library exposes commands +
      History undo/redo, not `NSMenu` policy.
- [ ] macOS UI test: an edit followed by Edit ▸ Undo (⌘Z) reverts it and Redo
      reapplies it, driven through the menu bar against the running app.

## Blocked by

- 07-mac-clipboard
- 08-shared-binding-table-format-menu
