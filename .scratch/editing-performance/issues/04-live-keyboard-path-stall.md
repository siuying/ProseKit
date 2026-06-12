# 04 — Live-keyboard path stall (first character after focus/Return)

Status: ready-for-human

## Symptom

In a document with many lines, pressing Return and then typing the first
character stalled for seconds; subsequent characters were fine. Reported
2026-06-12. All package benchmarks were green (~1 ms/key) at the time —
the cost lived entirely in the path they bypass.

## Diagnosis (2026-06-12, /diagnose loop)

Feedback loop: `ProseExampleUITests` typing through the real input stack
into the Example app with `-paragraphs 800`, plus temporary call-count/time
instrumentation over `ProseView`'s `UITextInput` surface (since removed).

Measured at 800 paragraphs (~184K chars), iPhone 17 Pro simulator:

- After focusing (any selection change, which includes the caret moving to
  a new block): UIKit's keyboard machinery issued **96 `text(in:)` + 86
  `offset(from:to:)` calls — a 22.9 s main-thread stall**. This is the
  user-visible "first character takes seconds".
- Steady state, between every two keystrokes: one full-document
  `text(in:)` (~120 ms) plus one full re-typeset (~52 ms) — ~180 ms/key
  against an 8.3 ms frame budget.
- `insertText` itself (model + incremental relayout): ~3 ms. Falsified:
  geometry queries, `hasText`, `draw`, the split's Changed Range.

Scaling check at 200 paragraphs confirmed the read costs quadratic
(16–17× change for a 4× size change) and the relayout linear.

## Convicted causes

1. **O(blocks²) character/position math.** `ProseView.plainText(from:to:)`
   and `characterOffset(of:)` called `Document.position(ofTextInBlockAt:)`
   per block, which `reduce`d `nodeSize` over the whole prefix — and
   `nodeSize` recursively re-counts string characters on every call. The
   keyboard reads document context through exactly these entry points
   around every keystroke, and ~180× after a selection change.
2. **Full re-typeset between keystrokes.** `UITextInteraction`'s selection
   chrome dirties layout every keystroke; `layoutSubviews` called
   `relayout()` with a nil Changed Range, taking the full-layout path and
   silently defeating issue 01's incremental relayout in the live app.

## Fix

- `Document` precomputes a per-block index at init (block start Positions,
  per-block text counts, cumulative counts) — same immutability argument
  as issue 02's `endTextPosition` cache. `position(ofBlockAt:)`,
  `textCount(ofBlockAt:)`, `textCharacters(beforeBlockAt:)`,
  `totalTextCount`, `endPosition` are O(1); `blockInfo(containing:)` is a
  binary search with the original boundary tie-break (pinned by an
  equivalence test against the linear scan).
- `ProseView`'s `plainText(from:to:)`, `characterOffset(of:)`,
  `position(atCharacterOffset:)` binary-search the block index and
  materialize text only for intersecting blocks; `hasText` is O(1).
- `ProseView.layoutSubviews` relayouts only when the width actually
  changed (edits relayout themselves with a Changed Range).

## Regression seams

- `testInteractionPathTypingManyPagesProse` now performs the observed
  per-keystroke UIKit work (full-document `text(in:)`, offset from
  document start, geometry, caret step, dirtied layout pass). Red with the
  bug: 2.603 s/50 keys (52 ms/key). Green with the fix: **0.115 s/50 keys
  (2.3 ms/key, rsd 5%)** — inside the 8.3 ms budget.
- `ProseExampleUITests.testLiveTypingAroundAParagraphBreakStaysResponsive`
  types through the real input stack at 800 paragraphs with a loose wall
  -clock bound; the focus storm alone violated it by 4×.
- `PositionTests.testBlockInfoMatchesLinearScanAtEveryPosition` pins the
  binary-search/linear equivalence including block-boundary ties.

## Outcome (800 paragraphs, live path)

| Bucket | Before | After |
|---|---|---|
| Focus/selection-change storm | 22,886 ms | 305 ms |
| Between keystrokes | ~180 ms | ~5.5 ms |
| `insertText` | ~3 ms | ~3 ms |

Full suite green: 35 macOS package tests, 52 iOS package tests (all
benchmarks held or improved), UI test green.

## What would have prevented this

The interaction-path benchmark (issue 01) existed precisely to avoid the
"benchmark says 2 ms but typing feels bad" trap, but its exercise list was
guessed rather than measured — it missed the full-document read, the
offset-from-start, and the dirtied layout pass that UIKit actually does.
When a benchmark exists to model an external caller, derive its workload
from instrumentation of that caller, not from intuition.
