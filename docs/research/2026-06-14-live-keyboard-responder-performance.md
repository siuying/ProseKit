# Live keyboard responder performance

**Date:** 2026-06-14
**Status:** Root cause found; fixes and benchmark gates added.

## What this is

A follow-up to the editing performance work after profiling the Simple Editor
sample. Instruments showed hangs around `ProseView.becomeFirstResponder()` and
SwiftUI async rendering. The visible symptom was a pause when focusing the editor
and typing the first few characters, even after the earlier incremental layout
optimizations.

The important measurement correction: wall-clock `app.typeText` timings from
XCUITest include large simulator keyboard/event-synthesis overhead. A native
`UITextView` measured through the same path is also multi-second. Use a
same-harness `UITextView` baseline before deciding whether Prose is slow.

## Reproduction

Use the example app UI tests. The real path must include UIKit keyboard focus,
`UITextInteraction`, autocorrection/tokenizer queries, and the input accessory
view when testing the Simple Editor.

Relevant tests:

- `Example/ProseExampleUITests/ProseExampleUITests.swift`
- `testLiveTypingUITextViewBaseline()`
- `testLiveTypingAroundAParagraphBreakStaysResponsive()`
- `testLiveTypingSimpleEditorStaysNearUITextViewBaseline()`

Relevant launch arguments:

- `-uitextview-paragraphs 800` shows a baseline `UITextView` with the same
  synthetic text as Prose.
- `-paragraphs 800` shows a bare `ProseView` on the same synthetic document.
- `-simple` deep-links to the Simple Editor with the SwiftUI input accessory
  toolbar.

## Baseline numbers

Measured on the simulator via XCUITest `app.typeText`, not direct `insertText`.
These numbers include simulator keyboard event synthesis and should not be read
as editor-only work.

| Scenario | First char after focus | Return | First char after Return | Second char after Return |
|---|---:|---:|---:|---:|
| `UITextView`, 800 paragraphs | 3.900 s | 3.504 s | 2.197 s | 2.082 s |
| Bare `ProseView`, 800 paragraphs | 3.499 s | 3.704 s | 2.325 s | 2.329 s |
| Simple Editor + accessory toolbar | 4.413 s | 4.377 s | 2.594 s | 2.701 s |

## Target

For this XCUITest harness, the gate is **4.5 s per typed event**. That target is
based on the same-harness `UITextView` baseline plus simulator variance. It is
not a statement that a real editor should take seconds to type; it is a guard
against regressions in this particular end-to-end test path.

For editor-only work, use the package performance tests and in-process snippets.
The 800-paragraph direct path measured separately during diagnosis was roughly:

| Operation | Prose cost |
|---|---:|
| Initial full layout | ~82 ms |
| Whole-document `text(in:)` | ~1.1 ms |
| First direct `insertText("a")` | ~2.3 ms |
| UIKit-style post-insert geometry/text probes | ~1.2 ms |
| Second direct `insertText("b")` | ~1.3 ms |

Those numbers explain why the multi-second XCUITest timings should be compared
against `UITextView`, not treated as direct editor latency.

## Findings

1. **Root cause: forced selection update during focus.**
   `ProseView.becomeFirstResponder()` activated `UITextSelectionDisplayInteraction`
   and immediately called `setNeedsSelectionUpdate()`. In the live
   responder/keyboard transaction, that forced UIKit selection-display work under
   `becomeFirstResponder()` and matched the Instruments stack around SwiftUI
   async rendering. Removing the forced update changed an in-process focus repro
   from timing out past 120 s to about 28 ms.

2. **Same-selection assignments amplified UIKit churn.**
   UIKit may set or ask for the current selection repeatedly during text
   interaction. `selectedTextRange` treated assigning the current range as a real
   selection change, notifying the input delegate and bumping host state. The fix
   makes same-selection assignment a no-op.

3. **The Simple Editor toolbar should not republish for unchanged toolbar state.**
   The toolbar is hosted in `inputAccessoryView` and observes `EditorProxy`.
   Normal typing often moves the Selection without changing active marks, block
   type, list state, or link/highlight affordances. `EditorProxy` now publishes
   only when that toolbar state actually changes, keeping ordinary typing from
   invalidating the SwiftUI toolbar unnecessarily.

4. **XCUITest wall-clock numbers are dominated by the simulator keyboard path.**
   A plain `UITextView` takes about 2-4 s per measured `app.typeText` event in
   this setup. The useful question for these UI tests is whether Prose stays near
   the `UITextView` envelope, not whether the absolute number is sub-frame.

## Changes made

- `Sources/ProseEditor/ProseView.swift`
  - `setSelectionDisplayActivated(_:)` now toggles `isActivated` only. It no
    longer forces `setNeedsSelectionUpdate()` during focus.

- `Sources/ProseEditor/ProseView+UITextInput.swift`
  - `selectedTextRange` setter returns early when the requested `TextSelection`
    equals the current Selection.

- `Tests/ProseEditorTests/ProseViewTests.swift`
  - Added a regression test that same-selection assignment does not notify the
    input delegate or call `onStateChange`.

- `Example/ProseExample/ProseExampleApp.swift`
  - Added a `UITextView` baseline route with `-uitextview-paragraphs`.
  - Shared synthetic paragraph generation between Prose and `UITextView`.
  - Changed `EditorProxy` to publish only meaningful toolbar-state changes.

- `Example/ProseExampleUITests/ProseExampleUITests.swift`
  - Added same-harness `UITextView` baseline coverage.
  - Tightened the Prose live-typing gate from 5.0 s to 4.5 s.
  - Added Simple Editor live-typing coverage with the same 4.5 s target.

## Verification

Successful checks during the investigation:

- `BuildProject(buildForTesting: true)` passed.
- `testLiveTypingUITextViewBaseline()` passed.
- `testLiveTypingAroundAParagraphBreakStaysResponsive()` passed with the 4.5 s
  target.
- `testLiveTypingSimpleEditorStaysNearUITextViewBaseline()` passed with the 4.5 s
  target.
- `testToolbarRebuildStaysCheap()` passed, reporting `0.0007 ms/rebuild over 400`.

A combined UI-test invocation exceeded the tool timeout. Running the UI tests one
at a time produced usable timing output. Direct `xcodebuild` from the sandbox was
blocked by SwiftPM/Xcode cache permissions, so use the Xcode build/test tools for
this project.

## Practical guidance

- When a future profile points at `becomeFirstResponder()`, check whether code is
  forcing selection display geometry during the responder transition. Let UIKit
  schedule selection updates unless a concrete user-visible bug requires manual
  invalidation.
- Do not compare XCUITest `app.typeText` wall-clock timings to direct editor
  benchmarks. Always collect a same-harness `UITextView` baseline.
- Keep host toolbar state derived and equatable. Rebuilding the toolbar on every
  caret move is avoidable work and makes keyboard-path profiles harder to read.
