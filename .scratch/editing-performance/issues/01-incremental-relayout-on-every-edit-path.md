# 01 — Incremental relayout on every edit path

Status: ready-for-agent

## What to build

Make every keystroke re-typeset only the Layout Boxes its Transaction
actually touched, by threading the **Changed Range** (see `CONTEXT.md`) from
the model layer into `IncrementalLayoutStore.layout(_:changedRange:)` — whose
reuse branch is dead code today because `ProseView.relayout()` never passes a
range.

### Why

Typing at the end of the many-pages fixture costs 19 ms/key against an
8.3 ms 120 Hz frame budget, because every keystroke re-typesets every block.
Cold layout is already fast (research finding #1); the entire gap is wasted
re-typesetting. Expected result: many-pages typing collapses to roughly the
one-page numbers (~2 ms/key).

### Model: the Changed Range lives on the Transaction (the why behind the where)

`ReplaceStep.apply` already computes a per-Step changed range in
`StepApplication`; `Transaction.apply` currently discards it. Computing the
range in the view layer instead was rejected because `runCommand` cannot know
what an arbitrary Command did — it would silently force full relayout on
Return, paste, and toggle-heading, reintroducing the cliff for exactly the
keys users notice.

- `AppliedTransaction` gains `changedRange: Range<Position>`, expressed in
  the *resulting* Document's Positions.
- `Transaction.apply` aggregates: fold over Steps, mapping the
  already-accumulated range forward through each subsequent Step via
  **Mapping** (do not hand-roll the arithmetic — `Mapping` exists for this),
  then union with that Step's own range.
- Every path that produces an `AppliedTransaction` must supply a range. That
  includes the paths that bypass `Transaction` today: the typing-marks branch
  of `EditorState.insertText` (`replaceDocument`), and the Commands that go
  through `Document.splitBlock` / `joinBackward` / `togglingHeading`. Those
  Document methods need to surface what they touched; a conservative
  over-wide range is acceptable where exactness is awkward (correctness
  backstop below catches over-reuse, and over-invalidation only costs speed).

### EditorState: keep only the last transaction

`dispatchedTransactions` is a write-only accumulator — nothing in Sources
reads it, and it retains a full Document snapshot per keystroke, unbounded.
Replace it with `lastTransaction: AppliedTransaction?`. History arrives later
as an Extension that observes dispatches (that is what **Origin** is for);
this array could not power real undo anyway (it carries no Steps). The two
tests asserting on accumulated origins get rewritten against
`lastTransaction`. Land this *before* re-measuring, so issue 03's gate sees
the cleaned state.

### View: pass the range through

`ProseView.relayout()` passes the latest Changed Range into the layout store.
Edit paths that relayout without a new transaction (e.g. width change in
`layoutSubviews`) pass nil and take the full-layout path, as today.

### Layout store: make reuse cheap and structural edits incremental

Two defects in the reuse branch to fix while wiring it up:

1. **Zero-delta fast path.** `LayoutBox.shifted(toY:positionRange:)` rebuilds
   the block's whole Line Fragment array even when both deltas are zero —
   every block *above* the edit pays it. Return `self` unchanged when
   `deltaY == 0 && deltaPosition == 0`. (This fast path is deleted wholesale
   by issue 02; it is cheap insurance for bisecting this issue's benchmark
   result, which is why the two are strictly sequenced.)
2. **Tail re-alignment.** Reuse aligns old and new blocks *by index*, so a
   block split (Return) or join (backspace at block start) misaligns every
   block below the edit and re-typesets the bottom half of the document.
   Because a Transaction's Changed Range is one contiguous region, alignment
   is arithmetic, not diffing: blocks entirely before the range align at the
   same index; blocks entirely after it align at
   `index + (oldChildCount − newChildCount)`.

The existing node-equality check (`oldChildren[i].node == block`) stays on
both sides as the correctness backstop: a wrong range may cost performance,
never a stale Layout Box.

### Interface sketch (decision-rich parts only)

```swift
public struct AppliedTransaction {
    public var document: Document
    public var selection: TextSelection
    public var origin: Origin
    public var changedRange: Range<Position>   // post-apply coordinates
}

public struct EditorState {
    public private(set) var lastTransaction: AppliedTransaction?
    // dispatchedTransactions: [AppliedTransaction] — removed
}
```

### New benchmarks (this issue adds measurements, not just speed)

- **Typing with paragraph breaks**: many-pages fixture, every 10th keystroke
  is Return — pins the tail re-alignment behavior; without it the alignment
  logic is correctness-tested but never performance-tested.
- **Interaction-path typing**: per keystroke, drive the surface UIKit
  actually exercises — `insertText`, then `caretRect(for:)`,
  `selectionRects(for:)`, and a tokenizer-style `position(from:offset:)`
  round-trip. This issue only *records* the number; issue 02 owns making it
  fast. It exists because the current benchmarks measure model + relayout
  only, which is the "benchmark says 2 ms but typing feels bad" trap.

### Out of scope

- Block-relative geometry, O(block) offset math, `endTextPosition` caching —
  issue 02.
- Any fix for the typing-at-start anomaly, including the `walkTextNodes`
  early-exit — issue 03 (gated; do not touch the model mid-measurement).
- Scrolling, draw-rect culling — future slice.

## Acceptance criteria

- [ ] Typing at end, many pages: ≤ 2.5 ms/key (baseline 19 ms/key)
- [ ] Typing with paragraph breaks, many pages: ≤ 2× plain typing-at-end
- [ ] rsd ≤ 20% on typing-at-end and paragraph-break scenarios
- [ ] Initial render and full-document layout benchmarks: no regression
- [ ] Correctness test: across a plain text edit, untouched Layout Boxes keep
      their `typesetID`s
- [ ] Correctness test: across a mid-document block split, every block below
      the split keeps its `typesetID` (tail re-alignment)
- [ ] Every `AppliedTransaction`-producing path supplies a Changed Range
      (insert, delete, replace, split, join, toggle-heading, typing-marks
      insert)
- [ ] `EditorState` no longer accumulates transactions; origin assertions
      rewritten against `lastTransaction`
- [ ] Interaction-path benchmark exists and its number is recorded in this
      issue's comments (no target yet — issue 02 owns it)

## Blocked by

None — can start immediately.

## Comments

### 2026-06-11 — implementation benchmark run

Branch: `editing-performance-01-incremental-relayout`

Verification:

- `swift test` passed: 31 tests, 0 failures.
- `xcodebuild test -scheme Prose-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ProseEditorTests/PerformanceTests` passed: 17 tests, 0 failures.

Measured ProseView averages from the simulator run, 50 keystrokes per editing iteration:

- Typing at end, many pages: 0.054 s total, about 1.08 ms/key, rsd 5.443%.
- Typing with paragraph breaks, many pages: 0.046 s total, about 0.92 ms/key, rsd 5.813%.
- Typing at start, many pages: 0.058 s total, about 1.16 ms/key, rsd 5.293%.
- Interaction-path typing, many pages: 2.608 s total, about 52.16 ms/key, rsd 25.379%. This is recorded as the before number for issue 02.
- Full layout, many pages: 0.016 s, rsd 7.391%.
- Initial render, many pages: 0.026 s, rsd 21.619%; average matches the baseline, with the first iteration as the outlier.
