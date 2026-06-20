# macOS render skeleton: read-only document in an NSScrollView Canvas

Status: ready-for-agent

Context: ADR 0009 (content-sized Mac Canvas), CONTEXT.md Canvas, Q6 (PlatformColor).

## What to build

A native AppKit `ProseView` (`NSView`) that renders a **Document** read-only and
scrolls, driven by the shared `EditorCore`. The **Canvas** is a content-sized,
flipped, **non-layer-backed** `NSScrollView.documentView` that paints the
**Layout Boxes** intersecting the visible `dirtyRect` via the existing CoreText
draw path; AppKit handles culling, so no manual repositioning-on-scroll. Expose
it to SwiftUI via an `NSViewRepresentable` and show it in the Example app on a
macOS destination.

Introduce the cross-platform color seam this requires: a `PlatformColor`
typealias (`UIColor`/`NSColor`) plus semantic accessors (`.label`,
`.canvasBackground`, system grays), and an `NSColor` twin for `HighlightColor`'s
dynamic dark-mode color. Fonts need no work (already `CTFont`). Dark-mode
resolves at draw time under each framework's current appearance.

Stand up the macOS Example app as a real deliverable, not a bare host: a
ProseExample macOS destination showing an editor demo. Adding the macOS
destination to the ProseExample Xcode project is part of this slice; if the
project can't be edited programmatically, wire up the SwiftUI host and call it
out for a human to attach the target.

Also establish the **macOS UI test target** for ProseExample, so every later
Mac slice lands its behavior tests against the running app (mirroring the
existing iOS `ProseExampleUITests`). This slice seeds it with a render/scroll
smoke test.

## Acceptance criteria

- [ ] Launching the Example app on macOS renders a sample Document and scrolls.
- [ ] The Mac Canvas is non-layer-backed (no `wantsLayer = true`) and flipped.
- [ ] Scrolling repaints only visible Layout Boxes (geometry stays
      translation-free — `GeometryMapper` rects pass through unchanged).
- [ ] Highlights render with correct light/dark colors on macOS.
- [ ] No `import UIKit` leaks into `EditorCore`; UIKit/AppKit code stays in the
      respective view shells.
- [ ] A macOS UI test target exists for ProseExample with a passing smoke test
      that launches the app and asserts the document renders.

## Blocked by

- 01-extract-editor-core
