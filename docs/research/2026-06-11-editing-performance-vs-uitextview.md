# Handoff: editing performance vs UITextView (optimization effort)

**Date:** 2026-06-11
**Branch:** `prose-slice-1-13-uitextinteraction`
**Status:** Benchmarks written and passing; optimization not started.

## What this is

We benchmarked ProseView (custom CoreText engine) against UITextView on the same
text — *The Last Question* by Isaac Asimov — at two sizes: one screen (~8
paragraphs) and many screens (story ×5, ~220 paragraphs, ~34K chars). The
benchmarks exist so the upcoming optimization work has a before/after baseline.

## Artifacts (do not duplicate; read these)

- `Tests/ProseEditorTests/PerformanceTests.swift` — paired Prose/UITextView
  benchmarks: initial render, full-document layout, typing at end/start,
  backspace. Matched styling (17pt system font, 12pt paragraph spacing,
  390×844 viewport) and a sanity test proving both views rasterize glyphs
  off-screen.
- `Tests/ProseEditorTests/TheLastQuestionFixture.swift` — fixture text with
  `onePage` and `manyPages` variants.

Run with:

```
xcodebuild test -scheme Prose-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ProseEditorTests/PerformanceTests
```

## Baseline numbers (iPhone 17 Pro simulator, 2026-06-11)

Averages over 10 `measure` iterations; editing = 50 keystrokes per iteration.

| Scenario | ProseView | UITextView |
|---|---|---|
| Initial render, one page | 13 ms | 18 ms |
| Initial render, many pages | 26 ms | 22 ms |
| Full document layout, many pages | 13 ms | 25 ms |
| Typing at end, one page | 1.7 ms/key | 0.9 ms/key |
| Typing at end, many pages | **19 ms/key** | 1.8 ms/key |
| Typing at start, many pages | **~114 ms/key (rsd 95%)** | 1.5 ms/key |
| Backspace at end, many pages | 17.5 ms/key | 83 ms/key (rsd 46%) |

## Findings

1. **Rendering is fine.** Cold layout + one-screen rasterization matches
   UITextView, and full-document CoreText layout is ~2× faster than forcing
   TextKit 2's `ensureLayout` over the same content. Do not spend effort here.

2. **Editing on large documents is the problem, and the first cause is known.**
   `ProseView.relayout()` (Sources/ProseEditor/ProseView.swift:66) calls
   `layoutStore.layout(state.document)` with **no `changedRange`**, so the reuse
   branch in `IncrementalLayoutStore.layout`
   (Sources/ProseEditor/Layout.swift:143) never fires — every keystroke
   re-typesets every block. 19 ms/key blows the 8.3 ms 120 Hz frame budget.
   The fix is to thread the edited Position range from each edit path
   (`insertPlainText`, `deleteBackward`, `replace`, `runCommand`) into
   `layout(_:changedRange:)`. Expected result: many-pages typing collapses to
   roughly the one-page numbers (~2 ms/key). The benchmarks above are the
   acceptance test.

3. **Unexplained: typing at start is ~6× slower than typing at end** (114 vs
   19 ms/key, rsd 95%). Full re-typeset cost is position-independent, so the
   extra cost — and the huge variance — must be in the model layer
   (`ReplaceStep` apply / `Document.replacingText` / transaction dispatch near
   position 2) or in `characterOffset(of:)`-style linear scans in ProseView.
   Diagnose before optimizing; fixing the `changedRange` plumbing first may
   change this number, so re-measure after fix #2.

4. **Caveat on the one Prose editing win:** UITextView's 83 ms/backspace is
   suspiciously slow with high variance — likely a TextKit 2 invalidation
   artifact in an unhosted view, not real-device behavior. Don't cite it as a
   win without re-measuring hosted/on-device.

## Known measurement caveats

- Views are unhosted (no UIWindow); rasterization goes through
  `UIGraphicsImageRenderer` + `layer.render(in:)`. The sanity test
  (`testRenderingBenchmarkDrawsGlyphsInBothViews`) confirms both views draw
  glyphs this way.
- Prose editing measures model + full relayout per keystroke (relayout is
  synchronous inside `insertText`); UITextView gets an explicit
  `layoutIfNeeded()` per keystroke to match. Neither measures actual screen
  compositing.
- `dispatchedTransactions` accumulates an `AppliedTransaction` (with a full
  Document snapshot) per keystroke — check whether that array's growth
  contributes to the editing numbers and the rsd.

## Suggested next steps (in order)

1. Thread `changedRange` from ProseView edit paths into the layout store
   (finding #2). Re-run the benchmarks; expect typing-at-end many-pages to
   drop ~10×.
2. Re-measure typing-at-start. If still disproportionate, diagnose the model
   layer (finding #3) — `/diagnose` is the right loop for it.
3. Consider draw-rect culling: `ProseView.draw(_:)` draws every line fragment
   on every redraw regardless of the dirty rect — irrelevant in these
   benchmarks (raster was one screen) but it will matter once scrolling lands.

## Suggested skills

- `/diagnose` — for the typing-at-start anomaly (finding #3); it's a
  performance regression hunt, not a known fix.
- `/tdd` — the existing benchmarks are the red/green signal for the
  `changedRange` fix; add a correctness test that incremental layout reuses
  untouched blocks (assert on `typesetID` stability across an edit).
- `/code-review` — before merging the optimization, the position-mapping math
  around block boundaries (see commit 74adf17) is easy to break.

## Repo conventions that apply

- Issues live under `.scratch/<feature>/` (see `docs/agents/issue-tracker.md`).
- No "Co-Authored-By: Claude" / "Generated with" trailers in commits.
- Domain language in `CONTEXT.md` (Position, Step, Transaction, Layout Box) —
  use it in any new code/docs.
