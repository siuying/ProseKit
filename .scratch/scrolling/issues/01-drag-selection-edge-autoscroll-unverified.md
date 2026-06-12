# 01 — Drag-selection edge autoscroll unverified

Status: ready-for-human (fallback implemented; needs device re-verification)

## What to verify

Scroll support landed (ADR 0002: `ProseView` is a `UIScrollView` with a
Viewport-sized Canvas). One behavior from the design session could not be
verified by automation: dragging a selection handle to the Viewport edge
must autoscroll, like UITextView.

The decision (2026-06-12 grilling session) was to rely on the system
selection machinery (`UITextInteraction` / `UITextSelectionDisplayInteraction`)
first, and implement our own edge-autoscroll fallback only if the system
does not drive it.

## What automation established

- Double-tap word selection, handles, and the edit menu all work in the
  scroll view (XCUITest probe, 2026-06-12).
- The probe could not reliably grab a selection handle by blind
  coordinates (handles expose no accessibility hooks), so the
  drag-to-edge-and-hold path was never exercised.

## How to verify manually

1. Launch the example app with `-paragraphs 100` (device or simulator,
   software keyboard visible).
2. Double-tap a word in the first screenful.
3. Drag the bottom selection handle to just above the keyboard and hold.
4. Expected: the document scrolls while the selection extends.

If it does not scroll: implement edge-autoscroll in `ProseView` — during a
selection-handle drag (observable via `selectionWillChange`/
`selectionDidChange` and touch location), drive `contentOffset` with a
display link while the touch stays inside an edge band. Keep
`scrollCaretToVisible` out of that path (see the caret-follow decision:
mid-drag reveals must not fight the drag).

## Comments

**2026-06-12 (maintainer, iPad):** Verified manually — the system does NOT
autoscroll. Selecting text and dragging the end handle to the bottom edge
extends the selection but never scrolls.

**2026-06-12 (agent):** Fallback implemented in `ProseView`: the system's
range-adjustment pan recognizer is observed via `addTarget` (matched by
type name — `testSystemSelectionDragGestureIsHooked` pins that the OS
still exposes it). While the drag sits in a 44pt edge band, a display
link scrolls the Viewport (step ramps with band penetration, clamped to
the content) and extends the Selection head to the Position passing under
the stationary finger. Covered by four `ScrollingTests`.

Remaining for a human:
- Re-run the manual steps above on device — the unit tests drive the seam
  below the real gesture, so the end-to-end handle drag still needs eyes.
- Caret drags (collapsed selection) are not autoscrolled yet; only range
  handle drags are. Extend if it feels wrong in use.
