# 06 — deleteBackward cost and variance (gated investigation)

Status: ready-for-human

## What to build

A measurement first, a diagnosis only if the measurement demands it — same
gate discipline as issue 03.

### Why

The 2026-06-12 full benchmark run (issue 04 validation) showed
`testDeleteBackwardManyPagesProse` at 0.196 s / 50 keys ≈ 3.9 ms/key with
rsd 53% — roughly 4× the typing-at-end scenarios and far outside the
slice's rsd ≤ 20% variance bar (which formally targets typing scenarios;
this issue decides whether delete joins them). No diagnosis was done; the
numbers come from before/after validation runs only, and the same run
showed UITextView's delete at 4.5 s (rsd 54%), so nothing is user-visibly
broken. Per the README's standing decision, nothing gets fixed before
instrumentation convicts it.

### The gate

1. Re-run the deleteBackward many-pages benchmark on the issue 04/05 tip
   and capture **per-iteration** values (XCTest prints them; rsd 53% with
   a first-iteration outlier is a known artifact shape — initial render
   shows the same).
2. **If the steady-state iterations are ≤ 2× typing-at-end and the
   variance is a first-iteration artifact**: record the numbers here,
   close by measurement. Optionally exclude warm-up via a primed first
   iteration if that makes the benchmark honest, but do not chase the
   number.
3. **If steady-state is > 2× typing-at-end or variance persists across
   iterations**: open a /diagnose loop seeded with the suspect list below;
   fix only what instrumentation convicts.

### Suspect list (hypotheses, not conclusions)

- `ProseView.deleteBackward` runs `Commands.joinBackward()` first on every
  keystroke; mid-paragraph deletes pay that failed attempt (blockInfo +
  guard work) before `state.deleteBackward()` does the real edit —
  possibly duplicated model work per key.
- `Document.replacingText` → `textRange(from:to:)` still uses
  `walkTextNodes`, the full-tree walk from issue 03's suspect list, still
  untouched by every slice. Position-independent, inflates inserts and
  deletes alike — if it were the cause, typing would show it too, so this
  alone cannot explain a delete-specific gap.
- The benchmark deletes 50 chars from the document end; the document is
  one block shorter each iteration only if it crosses a block boundary —
  check whether some iterations cross boundaries (join path, tail
  re-alignment) and others don't, which would be real bimodality, not
  noise.

## Out of scope

- Any model or view change before the gate decides.
- Draw costs — issue 05 (note: the delete benchmark does not rasterize,
  so issue 05 does not change this number).

## Acceptance criteria

- [ ] Per-iteration deleteBackward numbers recorded here alongside a
      same-run typing-at-end reference
- [ ] Gate applied: closed by measurement, or /diagnose findings documented
      with the convicted cause and instrumentation evidence
- [ ] If diagnosed: fix lands with a regression seam, full suite green

## Blocked by

None.

## Comments

### 2026-06-12 — closed by measurement (benchmark ordering artifact)

Branch: `editing-performance-04-live-keyboard-path-stall`

The >2× signal did not survive controlled measurement:

- Model layer is symmetric: `EditorState.insertText` and
  `EditorState.deleteBackward` both ~26 ms / 50 ops; the failed
  `joinBackward` attempt costs 0.3 ms / 50 (suspect 1 falsified).
- Interleaved view-level samples (fresh view per 50-op batch, alternating
  insert/delete batches within one test): insert median 157 ms/50, delete
  median 213 ms/50 — **1.36×**, fully overlapping distributions.
- Root cause of the recorded 3.9 ms/key rsd 53%: XCTest runs tests
  alphabetically, so `testDeleteBackwardManyPagesProse` is the first
  editing benchmark in the class and absorbed the process cold start
  (CoreText caches, first typeset) that the typing tests never paid.

Fix landed at the benchmark seam, not the editor: `warmUpEditingPath`
runs the editing path once on a throwaway view before any editing
measurement, making the benchmarks order-independent. Post-fix same-run
gate: delete 0.193 s vs typing 0.150 s per 50 keys — **1.29×**, below
the 2× bar.

Caveat recorded for future runs: the post-fix run happened on a loaded
machine (typing itself showed rsd 47% with a bimodal 0.07/0.25 shape in
both scenarios; the previous night's clean run had rsd 7%). The rsd ≤ 20%
target is only meaningful on a quiet machine; the delete/typing *ratio*
was stable across all three measurements. No model or view change is
warranted.

### 2026-06-12 — gate reopened by the larger fixture, re-closed under issue 07

The full-story fixture (905-block manyPages) reopened the variance: rsd
61% with a cooling trend (1.22 s → 0.23 s across iterations). Two causes,
both fixed under issue 07: the editing path's O(document) per-keystroke
terms amplified everything (steady-state was 4.6 ms/key), and the
insert/delete warm-up never crossed a block boundary, so the measured
iterations absorbed the joinBackward cold start. After the issue 07 fix
plus a delete-specific warm-up in `testDeleteBackwardManyPagesProse`:
0.68–0.94 ms/key, rsd 19.8% / 32.7% across two runs, delete/typing ratio
1.2–1.7× — under the 2× bar.
