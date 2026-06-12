# Editing performance

Make incremental editing on large documents hit the 120 Hz frame budget with
consistent keystroke latency. Scrolling is explicitly out of scope (ProseView
has no scroll container yet; that is a future slice).

Source material:

- `docs/research/2026-06-11-editing-performance-vs-uitextview.md` — baseline
  benchmarks and findings. The benchmarks in
  `Tests/ProseEditorTests/PerformanceTests.swift` are the acceptance tests.
- Runestone architecture study (external handoff) — consulted, deliberately
  not followed: its augmented red-black tree earns its keep at code-file
  scale (100K lines); a prose Document is hundreds to low-thousands of
  blocks, where a linear walk over value-type Layout Boxes is noise.

## Decisions (from the 2026-06-11 grilling session)

1. **The model layer owns the Changed Range.** `AppliedTransaction` carries
   the union of its Steps' ranges, carried forward via Mapping. The layout
   store's node-equality check stays as a correctness backstop. (Term added
   to `CONTEXT.md`.)
2. **O(blocks) per keystroke is the accepted asymptote for issue 01**, with
   block-relative geometry (issue 02) removing even that. Tripwire: if a
   hostile-size benchmark (~2,000 blocks) shows the walk itself breaking
   ~1 ms/key, issue 02's design is the escape hatch.
3. **Strictly sequenced.** Issue 02 does not start until issue 01's
   benchmarks are green, so a miss is bisectable.
4. **The typing-at-start anomaly is gated** (issue 03): re-measure after
   issue 01, diagnose only if still > 2× typing-at-end. No speculative fixes,
   including "obviously right" ones like the `walkTextNodes` early-exit.
5. **`EditorState` stops accumulating transactions.** History arrives later
   as an Extension that observes dispatches; an unbounded write-only array of
   Document snapshots is not a history store.

## Acceptance targets (many-pages fixture, vs 2026-06-11 baseline)

| Scenario | Baseline | Target |
|---|---|---|
| Typing at end | 19 ms/key | ≤ 2.5 ms/key |
| Typing at start | ~114 ms/key, rsd 95% | ≤ 2× typing-at-end |
| Typing with paragraph breaks (new) | unmeasured | ≤ 2× plain typing |
| Interaction-path typing (new) | unmeasured | ≤ 8.3 ms/key |
| Variance | rsd up to 95% | rsd ≤ 20% on all typing scenarios |
| Initial render / full layout | 26 ms / 13 ms | no regression |

## Issues

- `issues/01-incremental-relayout-on-every-edit-path.md` — AFK
- `issues/02-block-relative-geometry.md` — AFK, blocked by 01
- `issues/03-typing-at-start-anomaly-gated.md` — AFK, blocked by 01
- `issues/04-live-keyboard-path-stall.md` — diagnosed and fixed 2026-06-12
  (first char after focus/Return stalled seconds; O(blocks²) document reads
  on the UITextInput surface + full re-typeset from layoutSubviews)
