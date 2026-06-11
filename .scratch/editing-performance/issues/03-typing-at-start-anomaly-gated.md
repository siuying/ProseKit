# 03 — Typing-at-start anomaly (gated investigation)

Status: ready-for-human

## What to build

A measurement first, a diagnosis only if the measurement demands it. This
issue is deliberately *not* a fix: it can be closed by a number.

### Why

Baseline shows typing at the *start* of the many-pages fixture at
~114 ms/key with rsd 95% — ~6× typing at the end (19 ms/key) — and no
confirmed cause. Full re-typesetting is position-independent, so the gap
must come from elsewhere; but the baseline was taken while every keystroke
re-typeset 220 blocks, so the number was measured through fog. Issue 01
changes two of the prime suspects (full relayout per key, and the unbounded
`dispatchedTransactions` snapshot accumulation), so any fix committed before
re-measuring would be optimizing a symptom we cannot attribute.

### The gate

1. After issue 01 is green, re-run the typing-at-start many-pages benchmark
   (same fixture, same 50-keystroke protocol).
2. **If ≤ 2× typing-at-end**: record the number in this issue's comments,
   close the research doc's finding #3, done. No code changes.
3. **If > 2× typing-at-end**: open a `/diagnose` loop — reproduce, minimise,
   hypothesise, instrument — seeded with the suspect list below. Fix only
   what the instrumentation convicts, then re-run the full benchmark suite.

### Suspect list (hypotheses, not conclusions)

- `Document.replacingText` → `textRange` uses `walkTextNodes`, which
  recurses the entire tree even after finding its node (the `found == nil`
  guard skips the closure body, not the walk). Position-independent, so it
  cannot explain the *ratio* alone — but it inflates every edit and was
  deliberately left untouched by issue 01 to keep the measurement clean.
- The UITextInput geometry/offset paths, *if* the benchmark protocol
  exercises them at start but not at end (verify what the benchmark actually
  calls before believing this). Largely rewritten by issue 02, which is
  another reason this investigation may want to wait for or coordinate
  with it.
- The rsd-95% shape suggests something accumulating or episodic across the
  50-keystroke run; issue 01's `lastTransaction` change removes the known
  accumulator, so whatever variance survives it is a real signal.

### Out of scope

- Any speculative model-layer optimization before the gate decides.
- Performance targets for scenarios other than typing-at-start (owned by
  issues 01 and 02).

## Acceptance criteria

- [ ] Typing-at-start many-pages re-measured after issue 01, number recorded
      in this issue's comments alongside the same-run typing-at-end number
- [ ] Gate applied: closed-by-measurement (≤ 2×), or `/diagnose` findings
      documented here with the convicted cause and its instrumentation
      evidence
- [ ] Final state: typing at start ≤ 2× typing at end, rsd ≤ 20%
- [ ] Research doc finding #3 updated with the outcome

## Blocked by

- 01 — Incremental relayout on every edit path (the re-measurement is
  meaningless before it)

## Comments

### 2026-06-11 — closed by measurement

Branch: `editing-performance-03-typing-start-gate`

Gate result from the final issue-02 full performance run:

- Typing at end, many pages: 0.048 s per 50 keys, about 0.96 ms/key, rsd 7.407%.
- Typing at start, many pages: 0.053 s per 50 keys, about 1.06 ms/key, rsd 3.177%.
- Ratio: about 1.10x typing-at-end.

The anomaly is below the 2x gate, so no diagnosis or code change is needed for
this issue. Research finding #3 was updated to record the outcome.
