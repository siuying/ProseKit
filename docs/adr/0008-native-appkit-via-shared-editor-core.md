# ADR 0008: macOS is native AppKit over a shared EditorCore, not Catalyst

Date: 2026-06-20

## Decision

The Mac editor is a native AppKit view (`NSView`/`NSScrollView` +
`NSTextInputClient`), not a Mac Catalyst port of the UIKit `ProseView`. The
platform-free orchestration — document, layout store, geometry, command
dispatch — is lifted out of `ProseView` into a plain `@MainActor` **EditorCore**
that both platforms drive. Each platform ships a thin view shell that owns only
what the system forces onto the responder: input-protocol conformance
(`UITextInput` / `NSTextInputClient`), scrolling, and its **Selection Layer**.

## Considered Options

- **Mac Catalyst** — reuse the UIKit `ProseView` essentially unchanged.
  Rejected: cheapest, but ships the iPad-app-on-Mac feel (UIKit text
  interaction, non-native scrollers/menus/cursor) and wastes the platform-free
  architecture the model and CoreText layout already invested in.
- **SwiftUI text view** — not viable; the engine is a custom CoreText layout,
  not a droppable `TextView`.

## Consequences

- AppKit's `NSTextInputClient` draws **no** selection chrome, so the caret and
  range highlight become an editor-owned **Selection Layer** sibling above the
  **Canvas** (the Canvas stays authority-free on both platforms). On iOS that
  same role is the system's `UITextInteraction`.
- Mac key input routes through `NSTextInputClient` + `doCommand(by:)` mapped to
  the **Command** layer, rather than raw `keyDown` parsing — the OS-resolved
  semantic selectors (word/line motion, deletions) become a free, conventional
  keymap.
- Editor-specific shortcuts (⌘B/⌘I, Tab/Shift-Tab) move into a shared neutral
  binding table, realized per-platform (menu key-equivalents + `doCommand` on
  Mac, `UIKeyCommand` on iOS). The **Extension**-contributed keymap described in
  `CONTEXT.md` stays future work and is out of scope for this effort.
- Undo/Redo on the Mac Edit menu binds to the Step-based **History** (ADR 0004),
  never `NSUndoManager`, even though AppKit's responder chain reaches for the
  latter by default.
