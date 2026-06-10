# 01 — Walking skeleton: render a static Document

Status: done

## What to build

Stand up the whole `Prose` structure and prove the model→layout→view→app spine
with a non-interactive render. A SwiftPM package `Prose` with two modules —
`ProseModel` (pure, no UIKit) and `ProseEditor` (CoreText view) — plus a minimal
Xcode iOS example app in `Example/` that hosts the view.

In `ProseModel`, the minimum to *spell* and validate a document: immutable
`Node`/`Mark`/`Attrs`, a `Schema` declaring the slice-1 types (`doc`, `paragraph`,
`heading(level)`; marks `bold`, `italic`, `code`), the integer token-counting
`Position` scheme, and `Document ↔ JSON` (ProseMirror-shaped) serialization.

In `ProseEditor`, the block-based layout: each leaf Block Node becomes a leaf
Layout Box typeset via CoreText into Line Fragments; container Boxes stack
children vertically. A single content `UIView` renders the visible boxes in
`draw(_:)`. No caret, no editing, no input.

The example app loads a hardcoded `doc(heading("Hello"), paragraph("world"))`
(decoded from JSON) and displays it as styled text — heading visibly larger than
the paragraph.

The Document tree is the structural authority; layout reads from it, never the
reverse.

## Acceptance criteria

- [ ] `swift build` produces `ProseModel` and `ProseEditor`; `ProseModel` has no UIKit import
- [ ] `Document ↔ JSON` round-trips a `doc(heading, paragraph)` fixture (unit-tested)
- [ ] `Position` token-counting is unit-tested against a known document layout
- [ ] Schema rejects an invalid document (e.g. a mark on a block, a disallowed child)
- [ ] Example app launches in the simulator and renders the hardcoded document with the heading visibly larger than the paragraph
- [ ] Layout produces one leaf Layout Box per leaf block; container boxes stack children vertically (assertable off-screen)

## Blocked by

None - can start immediately
