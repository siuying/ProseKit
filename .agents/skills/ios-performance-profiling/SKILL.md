---
name: ios-performance-profiling
description: Profile and optimize iOS app performance regressions with reproducible baselines, Instruments/Xcode evidence, simulator or device validation, and same-harness comparisons such as UITextView vs a custom editor. Use when an iOS feature feels slow, hangs, janks, regresses typing/scrolling/focus, or the user asks to profile, benchmark, investigate performance, or compare against a native control.
---

# iOS Performance Profiling

Use this skill when an iOS performance issue needs evidence, not guesses. The aim is a tight loop:

1. Reproduce the user-visible slowdown.
2. Establish a same-harness baseline.
3. Find the hot path with profiling or targeted measurements.
4. Fix the smallest real cause.
5. Gate the behavior with a benchmark or regression test.

Read [REFERENCE.md](REFERENCE.md) when you need deeper guidance on profiling tools, common traps, or interpreting UIKit/SwiftUI results. Read [EXAMPLES.md](EXAMPLES.md) for concrete task patterns. Use `scripts/extract_timings.py` when test logs contain repeated timing lines.

## When To Profile

Profile when any of these are true:

- The user reports visible lag, hangs, jank, delayed input, slow focus, or scroll hitching.
- A change is meant to improve performance and needs proof.
- Wall-clock behavior differs from unit or microbenchmark expectations.
- The suspected path crosses UIKit, SwiftUI, CoreAnimation, keyboard, text input, scrolling, drawing, layout, networking, storage, or concurrency.
- The proposed fix is not obvious enough to verify by inspection.

Do not start by refactoring. First build a feedback loop that reproduces the symptom the user actually sees.

## Workflow

### 1. Define the Symptom

Write the symptom in user-visible terms:

- Action: focus editor, type first character, scroll list, open sheet.
- Surface: simulator, device, XCUITest, manual repro, Instruments trace.
- Failure mode: hang duration, frame hitch, CPU spike, memory growth, repeated layout, dropped frames.

If the user provided an Instruments screenshot, use it to seed hypotheses, but do not treat a highlighted frame as root cause until you reproduce and falsify alternatives.

### 2. Build a Same-Harness Baseline

Compare against something that uses the same outer harness:

- Custom text editor vs `UITextView` through the same XCUITest `app.typeText` path.
- Custom scroll view vs `UITableView`/`UICollectionView` under the same scroll metric.
- Custom drawing vs a known simple rendering path in the same viewport.

Important: XCUITest, simulator keyboard, and first-launch setup can dominate wall-clock numbers. A 3s `app.typeText` call may be mostly event synthesis. Always measure a native baseline before setting a target.

### 3. Create a Fast Probe

Use the fastest faithful probe available:

- Unit or in-process benchmark for pure model/layout/drawing work.
- `RunCodeSnippet` for quick UIKit/editor helper timings.
- XCUITest for keyboard, focus, scrolling, or full interaction paths.
- Simulator/device screenshot validation for visual side effects.
- Instruments when call stacks, hangs, allocations, or frames are unclear.

Keep each probe narrow. Split measurements by phase: focus, first type, edit, layout, draw, post-edit UIKit queries, toolbar refresh, scroll.

### 4. Generate Falsifiable Hypotheses

List 3-5 ranked hypotheses before editing. Each must predict a measurable change.

Example:

- If forced selection display update is the cause, removing/debouncing it will make `becomeFirstResponder()` complete quickly.
- If layout is the cause, direct `insertText` on a large document will be slow even without XCUITest.
- If accessory SwiftUI toolbar rebuild is the cause, bare editor typing will be fast while Simple Editor typing remains slow.

### 5. Instrument Sparingly

Prefer timings around boundaries over broad logging:

- responder/focus start and end
- input delegate notifications
- model edit
- layout
- draw invalidation
- geometry/text input queries
- SwiftUI accessory/toolbar publish or render

Use unique debug prefixes only if logs are needed, then remove them before finalizing.

### 6. Fix The Smallest Cause

Fix the actual hot path, not a nearby expensive-looking function. Good fixes often look like:

- avoid forced UIKit work inside responder transitions
- no-op redundant state assignments
- coalesce or compare derived UI state before publishing
- reuse layout/drawing for unchanged regions
- avoid whole-document reads in per-keystroke paths
- defer non-visible work until after interaction

### 7. Gate The Result

Add a regression test or benchmark at the closest faithful seam:

- same-harness UI test for keyboard/scroll/focus behavior
- in-process performance test for model/layout/drawing
- unit test for no-op behavior or cache reuse
- research note if the main finding is methodology or baseline interpretation

State the target and why it is fair. If XCUITest is the harness, base the target on a native control in the same harness.

## Output Expectations

When reporting back:

- Give the root cause in one sentence.
- Include the baseline, target, and before/after timings.
- Say which hypotheses were falsified.
- List changed files and verification commands/tests.
- Call out harness limitations, especially simulator and XCUITest overhead.
- If you added a research note, link it.

## Cleanup

Before finishing:

- Remove temporary logs, debug prefixes, and throwaway instrumentation.
- Do not include Xcode user state or scheme rewrites unless intentional.
- Keep unrelated dirty files unstaged.
- Build or run the narrowest meaningful tests.
