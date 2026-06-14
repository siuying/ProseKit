# Examples

## Example 1: Live Typing Feels Slow

User request:

> The editor hangs when I open the Simple Editor and start typing. Instruments points at `becomeFirstResponder`. Please find and fix the root cause.

Good agent behavior:

1. Reproduce with the Simple Editor.
2. Add or run a same-harness `UITextView` baseline through `app.typeText`.
3. Measure bare editor and Simple Editor separately.
4. Probe `becomeFirstResponder()` in-process.
5. Test hypotheses:
   - forced selection update during focus
   - slow `UITextInput` helper methods
   - SwiftUI accessory toolbar rebuild
   - model/layout edit path
6. Fix only the confirmed cause.
7. Add regression tests and a research note.

Expected report shape:

```markdown
Root cause: forcing `UITextSelectionDisplayInteraction.setNeedsSelectionUpdate()`
during `becomeFirstResponder()` caused UIKit selection-display work inside the
keyboard responder transition.

`UITextView` baseline: ...
Prose before/after: ...
Verification: ...
```

## Example 2: Scroll Jank

User request:

> Fling scrolling in the large document sample looks choppy. Profile and rework it.

Good agent behavior:

1. Run the existing scroll UI test/signpost metric if present.
2. Compare against a native scroll view with similar content if possible.
3. Separate scroll event handling from drawing:
   - is layout happening during scroll?
   - is every frame repainting the full document?
   - is the canvas viewport-sized or content-sized?
4. Use screenshot/simulator verification for visual regressions.
5. Gate with a scroll metric and a trailing typing sanity check.

Potential fixes:

- repaint only the viewport
- cull draw calls to dirty rect
- avoid relayout in `layoutSubviews` unless width changes
- reuse per-block drawing/layers only if the simpler path cannot hit target

## Example 3: First Launch Is Slow

User request:

> The first time this screen opens it stalls, but later interactions are fine.

Good agent behavior:

1. Measure cold and warm separately.
2. Check first-time costs:
   - CoreText/font cache warmup
   - SwiftUI host creation
   - initial full layout
   - package/model fixture construction
   - keyboard/input view creation
3. Decide whether the user-visible target is cold or warm.
4. Avoid optimizing warm paths if only cold start fails.

## Example 4: Benchmark Numbers Look Terrible

User request:

> XCUITest says typing takes 3 seconds per key. Make it 16ms.

Good agent behavior:

1. Do not accept the absolute XCUITest number as editor latency.
2. Benchmark `UITextView` in the same XCUITest harness.
3. Add direct in-process measurements for editor-only work.
4. Explain the split:
   - same-harness UI test target for end-to-end regressions
   - direct benchmark target for editor internals

A good outcome may be:

- XCUITest gate: custom editor stays near `UITextView`
- direct benchmark gate: edit/layout stays under frame budget
