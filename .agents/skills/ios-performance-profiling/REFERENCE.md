# iOS Performance Profiling Reference

## Tool Selection

| Need | Best tool |
|---|---|
| Compile and link check | Xcode `BuildProject` |
| Fast Swift/UIKit probe | Xcode `RunCodeSnippet` |
| Live keyboard/focus/scroll path | XCUITest through `RunSomeTests` |
| Visual layout validation | Simulator launch + screenshot |
| CPU hot path | Instruments Time Profiler |
| Main-thread hangs | Instruments Hangs or Time Profiler with thread view |
| Scroll/render frame pacing | XCTest signpost metrics, Instruments Core Animation |
| Allocations/retains | Instruments Allocations/Leaks |
| Apple API uncertainty | `DocumentationSearch` |

Prefer Xcode MCP tools in Xcode sessions. Use shell `xcodebuild` only when the Xcode tool path is unavailable, and expect sandbox/cache permissions to block direct builds in some environments.

## Same-Harness Baselines

A baseline is only useful if it shares the same expensive outer machinery.

Examples:

- `app.typeText` custom editor vs `app.typeText` `UITextView`
- fling custom scroll view vs fling `UITableView`
- same simulator/device, same OS, same run destination
- same document size and roughly same visual styling

Do not compare XCUITest wall-clock typing against direct `insertText`. They answer different questions.

## Common iOS Performance Traps

### Responder and Keyboard

Potential symptoms:

- first focus hangs
- first character is much slower than later characters
- `becomeFirstResponder()` appears in Instruments stack
- SwiftUI async renderer appears above UIKit responder work

Likely causes:

- forcing selection/caret updates inside responder transition
- reloading input views repeatedly
- expensive `inputAccessoryView` host rebuild
- redundant `selectedTextRange` assignment notifications
- keyboard notification handler doing layout or scroll work repeatedly

Probes:

- measure `becomeFirstResponder()` in-process
- compare bare editor vs editor with accessory view
- count host state publishes during one focus/type event

### UITextInput Bridges

UIKit may call these frequently:

- `selectedTextRange`
- `text(in:)`
- `offset(from:to:)`
- `position(from:offset:)`
- `caretRect(for:)`
- `selectionRects(for:)`
- `closestPosition(to:)`

Each should avoid whole-document walks where possible. For custom rich text, use indexes, binary search, cached layout geometry, and no-op guards for repeated assignments.

### SwiftUI Hosts Around UIKit

SwiftUI can make a small UIKit cost look large if host state changes too often.

Watch for:

- `@Published` revision counters bumped on every caret move
- `.id(revision)` forcing tree teardown
- derived toolbar state recomputed and published even when equal
- `UIHostingController` sizing work during keyboard transitions

Fixes:

- publish derived equatable toolbar state only when changed
- separate benchmark-only revision bumps from real state
- avoid identity changes for accessory views

### Layout and Drawing

Separate model, layout, invalidation, and draw:

- direct edit cost can be low while draw is slow
- layout can be fast while invalidating the full viewport is slow
- scroll can be slow because every frame repaints too much
- nested or non-flat documents may bypass incremental fast paths

Probes:

- direct `insertText` timing
- layout store timing with changed range
- dirty rect size and repaint count
- frame pacing under scroll metrics

## Setting Targets

Targets should be:

- tied to a native same-harness baseline when available
- loose enough for simulator variance
- tight enough to catch the regression
- documented in the test or research note

Example:

If `UITextView` through XCUITest measures 3.9s first char, 3.5s Return, and 2.1s steady typing, a 4.5s gate may be fair for the same XCUITest harness. That does not mean real editor latency should be seconds; it means the harness overhead dominates.

## What To Document

For durable findings, add a dated note under `docs/research/` with:

- symptom and reproduction
- profiling artifact summary
- baseline and target
- before/after numbers
- root cause
- fixes
- verification
- caveats about simulator, XCUITest, or profiling tool limits

Use markdown tables with leading and trailing pipes.
