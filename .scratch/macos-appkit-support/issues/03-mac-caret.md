# macOS caret: Selection Layer renders a blinking insertion point

Status: ready-for-agent

Context: CONTEXT.md Selection Layer, Q2 (sibling overlay), Q8 (pure renderer).

## What to build

A **Selection Layer** sibling above the Canvas that draws the blinking insertion
point for a collapsed **TextSelection**. A mouse click in the document places
the caret: the view shell translates the point through the shared
`GeometryMapper` (`closestPosition`) and dispatches a selection Command; the
Selection Layer only renders. The Canvas keeps no selection chrome (its
authority-free role is unchanged on both platforms).

Honor the AppKit conventions: the caret is hidden when the view is not first
responder, blinks only when it is, and uses the system blink cadence (paused
while typing).

## Acceptance criteria

- [ ] Clicking in the document places a caret at the nearest **Position**.
- [ ] Caret blinks at the system cadence while the view is first responder.
- [ ] Caret is hidden when the view resigns first responder.
- [ ] Caret geometry comes from the shared `GeometryMapper` (same query path as
      iOS), not a Mac-only computation.
- [ ] The Canvas draws no caret; only the Selection Layer does.
- [ ] macOS UI test: clicking in the document places the caret; the caret
      disappears when focus leaves the editor.

## Blocked by

- 02-mac-render-skeleton
