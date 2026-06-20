# ADR 0009: The macOS Canvas is content-sized, amending ADR 0002

Date: 2026-06-20

## Decision

On macOS the **Canvas** is a content-sized, flipped, non-layer-backed
`NSScrollView.documentView`, not the viewport-sized surface ADR 0002 adopted
for iOS. AppKit hands `draw(_:)` only the visible `dirtyRect` and clips
automatically, so no manual repositioning-on-scroll is needed.

## Context

ADR 0002 sizes the iOS Canvas to the **Viewport** and repositions it on scroll
specifically because a `UIScrollView` is layer-backed: a content-sized drawing
view would allocate a backing layer that scales with document height (hundreds
of MB on the synthetic benchmarks). A non-layer-backed `NSView` has no such
backing store — it draws its visible rect straight into the window — so the
problem ADR 0002 solved does not exist on AppKit, and importing its workaround
would forfeit translation-free geometry for nothing.

## Consequences

- The **Canvas** domain role is unchanged on both platforms ("paints the Layout
  Boxes intersecting the Viewport, holds no authority"); only its *sizing* is
  platform-specific — viewport-sized + manually repositioned on iOS,
  content-sized + AppKit-culled on Mac.
- Geometry stays translation-free, exactly the property ADR 0002 prizes: a
  flipped `documentView`'s own coordinate space *is* content space, so every
  `GeometryMapper` rect passes through unchanged.
- The Mac Canvas must **not** set `wantsLayer = true`, or it reintroduces the
  giant backing store the iOS viewport-sizing exists to avoid.
