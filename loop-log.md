# Autoloop Log

**Problem**: #102 — Turn editor-only perf benchmarks (typing latency, initial
layout, Prose vs UITextView) into checked-in baselines with explicit thresholds
that fail the test run on a regression, on the pinned canonical simulator.
**Signal**: `scripts/test-ios.sh -only-testing:ProseEditorTests/PerformanceGateTests` → pass/fail + printed medians
**Started**: 2026-07-01
**Baseline**: no enforced gate exists (measure-only, never fails CI)

## Iterations

| # | commit  | metric | Δ | review | status | description |
|---|---------|--------|---|--------|--------|-------------|
| 1 | 9c817e1 | gate green + bites | n/a | pass | keep | baseline gate: PerformanceBaseline + PerformanceGateTests, recorded medians on canonical sim, thresholds enforce regression, doc updated |
| 2 | (docs)  | —      | — | pass | keep | README documents the gate in the test loop |

## Verification evidence

- Baseline medians stable to <2% across 3 canonical-sim runs: initial full
  layout 36.5/36.6/36.2 ms; typing-at-end 1.40/1.41/1.39 ms/key;
  typing-at-start 1.65/1.66/1.68 ms/key; full-layout Prose/UITextView
  0.60/0.65/0.67×.
- Gate passes with real thresholds (exit 0).
- Gate proven to bite: temporarily lowering the typing-at-end ceiling to
  0.5 ms/key failed the run (exit 65) with a clear over-ceiling message,
  then reverted.

## Notes / follow-ups

- No dedicated iOS CI workflow exists yet (only interop.yml). The gate is
  enforced by any run of the iOS suite (scripts/test-ios.sh). Wiring a macOS
  GitHub Actions job that boots the pinned simulator is a separate decision —
  absolute perf gates on shared runners are variance-prone, which is why the
  design pairs them with a host-independent Prose/UITextView ratio gate.
