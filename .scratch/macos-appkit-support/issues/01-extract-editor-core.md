# Extract a shared, platform-free EditorCore

Status: ready-for-agent

Context: ADR 0008 (native AppKit over a shared EditorCore).

## What to build

Lift the platform-free orchestration out of the UIKit `ProseView` into a plain
`@MainActor` `EditorCore` that owns the **Document**/**EditorState**, the layout
store, the current `LayoutBox`, the `GeometryMapper`, `relayout()`, and
**Command** dispatch — with zero UIKit imports. The iOS `ProseView` becomes a
thin shell that drives this core and retains only what the system forces onto
the responder: `UITextInput` conformance, scrolling, and selection chrome.

This is a behavior-preserving refactor. No user-visible change on iOS; the value
is the seam that the macOS view will later drive.

## Acceptance criteria

- [ ] `EditorCore` compiles with no `import UIKit` / `import AppKit`.
- [ ] `EditorCore` owns document/state, layout store, `LayoutBox`,
      `GeometryMapper`, `relayout()`, and command dispatch.
- [ ] iOS `ProseView` forwards to `EditorCore` and owns only input-protocol
      conformance, scrolling, and selection chrome.
- [ ] The full existing iOS test suite passes unchanged (no behavior drift).
- [ ] No regression in the live-keyboard / scroll benchmarks.

## Blocked by

None - can start immediately.
