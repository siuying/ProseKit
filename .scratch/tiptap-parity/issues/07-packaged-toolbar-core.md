# 07 — Packaged toolbar core

Status: ready-for-agent

## What to build

A packaged `UIInputView`-based toolbar attached as the editor's
`inputAccessoryView` (Q4c), plus the headless command + active-state surface it
sits on (that surface largely exists after slice 06: `isActive(_:)`,
`activeBlockType`, `activeHeadingLevel`, the `toggle*`/`setTextAlign`/`setLink`
Commands; `canUndo`/`canRedo` arrive with the history slice).

- Horizontally scrollable on iPhone.
- H1–H4 and list types presented as `UIMenu` dropdowns; mark toggles as buttons
  reflecting `isActive`.
- Undo / redo buttons (need the history slice).
- Apps can replace the whole toolbar — it is a default, not a requirement.

## Acceptance criteria

- [ ] a default toolbar shows as `inputAccessoryView`, horizontally scrollable
- [ ] mark buttons reflect and toggle active state via the slice-06 API
- [ ] a heading dropdown (1–4) sets/clears the block heading level
- [ ] undo/redo buttons reflect `canUndo`/`canRedo` (history slice)
- [ ] the toolbar is replaceable by the host app

## Blocked by

- 06 — Active-state API + level-aware headings.
- prose-slice-1/07 — history (for undo/redo + canUndo/canRedo).

## Comments

2026-06-12: ready-for-agent. UIKit UI: unit tests can cover the view's binding to
the headless API, but the real interaction (scroll, menus, accessory presentation)
needs app verification on a device/simulator. Build the binding test-first; verify
the chrome by running the example app.
