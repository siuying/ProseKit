# ADR 0002: Viewport-sized canvas inside a UIScrollView subclass

Date: 2026-06-12

## Status

Accepted

## Context

`ProseView` needs to scroll like a native text view. A `UIScrollView` scrolls by
moving its `bounds.origin`, so the scroll view's own `draw(_:)` content cannot
scroll — the pixels must live in something that moves with the content. The
existing CoreText draw path (`draw(_:)` with block-accurate dirty-rect culling)
and the `UITextInput` geometry both assume a single flat coordinate space.

## Decision

`ProseView` becomes a `UIScrollView` subclass and **remains the `UITextInput`
and first responder**, like `UITextView`. Drawing moves to a private,
**viewport-sized Canvas** subview that is repositioned on scroll and repaints
the Layout Boxes intersecting the Viewport (drawing translated by
`contentOffset`). The Canvas is a dumb paint surface: `isUserInteractionEnabled
= false`, no geometry authority.

`contentSize` comes from eager full-document layout (the root `LayoutBox`
height); lazy/estimated layout is explicitly out of scope.

## Considered Options

- **Content-sized canvas** (naive `_UITextContainerView`): rejected — the layer
  backing store scales with document height, so the large synthetic benchmark
  documents would allocate hundreds of MB.
- **Per-block layers/views with recycling** (Runestone / TextKit 2 style):
  rejected for now — best scroll performance, but replaces `draw(_:)`,
  `editDirtyRect`, and the dirty-rect invalidation model wholesale. Remains the
  escape hatch if the scroll benchmark shows per-frame viewport redraw cannot
  hold frame rate.

## Consequences

- Geometry stays free of translation: a scroll view's own coordinate space *is*
  content space (`bounds.origin == contentOffset`), so every `GeometryMapper`
  rect (`caretRect`, `selectionRects`, `closestPosition`) passes through
  unchanged, and system selection chrome scrolls with the content for free.
- Scrolling repaints the visible Line Fragments every frame. This cost is
  pinned by a scroll benchmark in the example app's UI test target
  (`-paragraphs` synthetic document, hitch/frame-time metrics), alongside the
  existing live-keyboard typing benchmark.
- The `draw(_:)` coordinate flip can no longer use `bounds.height` of the text
  view; it must flip within the Canvas's own space.
- Deliberate divergence from `UITextView`: ProseView adjusts its own
  `contentInset` for the keyboard (opt-out flag), because caret-follow is
  built in and would otherwise reveal carets underneath the keyboard.
