# 14 — Scrolling & keyboard avoidance

Status: needs-triage

## What to build

Documents taller than the viewport are unreachable today: `ProseView` is a
non-scrolling `UIView` hosted full-window, and the example app papers over the
keyboard with `.ignoresSafeArea(.keyboard)`.

Regular-editor behaviors that depend on scrolling:

- Content taller than the screen is scrollable.
- Scroll-to-caret when typing past the visible area.
- Autoscroll while a selection-handle drag reaches the screen edge.
- Keyboard avoidance (and removal of the `.ignoresSafeArea(.keyboard)` hack).

## Open architecture fork (decide here, not before)

`ProseView` as a `UIScrollView` subclass (the `UITextView` shape) versus
`ProseView` as a document view hosted inside a separate scroll view. Decided
during the 2026-06-10 grilling to defer this choice deliberately: it should be
made together with the long-document rendering strategy (the current
full-redraw `draw(_:)` won't survive long documents; per-block layers/tiling
will force the same conversation). Until then, the property that keeps both
options open: all `UITextInput` geometry answers stay in `ProseView`'s own
coordinate space.

## Acceptance criteria

- [ ] A document taller than the screen can be scrolled and edited throughout
- [ ] Typing at the bottom keeps the caret visible (scroll-to-caret)
- [ ] Dragging a selection handle to the screen edge autoscrolls
- [ ] The keyboard does not cover the caret; the example app no longer ignores the keyboard safe area
- [ ] Loupe/handles/caret from issue 13 remain correctly positioned while scrolled

## Blocked by

- 13 — System selection UX via UITextInteraction
