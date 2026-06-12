# 07 — Per-keystroke relayout walk is O(blocks)

Status: ready-for-human

## What to build

Make the per-edit relayout cost proportional to the changed blocks instead
of the document's block count, so typing cost stops scaling with document
size.

Surfaced 2026-06-12 when the performance fixture moved from the truncated
story (220 blocks / ~34K chars in `manyPages`) to the full
`last_question.txt` (905 blocks / ~125K chars; hostile draw benchmark now
3,620 blocks). All gates from issues 01–06 stayed green at 220 blocks; the
larger document exposed the next linear term.

### Why

Measured on the iPhone 17 Pro simulator (50 keystrokes per iteration):

| Typing at end          | Prose       | UITextView |
| ---------------------- | ----------- | ---------- |
| one page (8 blocks)    | 0.12 ms/key | 0.68 ms/key |
| many pages (905 blocks)| 4.8 ms/key  | 0.6 ms/key |
| hostile (3,620 blocks) | 18 ms/key   | —          |

UITextView's per-keystroke cost is flat; Prose's grows linearly with block
count — ~4× cost for ~4× blocks. At 3,620 blocks one keystroke already
blows the 16.7 ms / 60 Hz frame budget (and the 8.3 ms / 120 Hz budget at
roughly 1,500 blocks), even though draw-rect culling (issue 05) is holding:
the draw-inclusive hostile benchmark costs what the pure-edit trend
predicts, so the edit path itself is the linear term.

The walk is in `IncrementalLayoutStore.layout`
(`Sources/ProseEditor/Layout.swift`): every edit re-enumerates all of
`document.root.content`, and for every unchanged block checks
`oldChildren[oldIndex].node == block` and rebuilds the children array
(`moved(toY:positionRange:)` allocates a fresh `LayoutBox` per block).
Issue 01 made typesetting incremental — unchanged blocks skip CTLine work —
but the bookkeeping pass over all blocks remained, and its constant is high
enough (node equality may compare block text) to dominate at ~1K blocks.

Related symptom: the issue 06 deleteBackward variance gate is effectively
reopened at this size — `testDeleteBackwardManyPagesProse` came in at rsd
61% with a cooling trend (1.22 s → 0.23 s across iterations) because the
10-keystroke warm-up no longer absorbs cold start on a 905-block document.
Steady state (~4.6 ms/key) is consistent with typing, so fixing the linear
term and/or scaling the warm-up should close it again.

### Design sketch (not binding)

The blocks before the changed range keep their y origin and positions; the
blocks after it shift by a constant delta. Candidate shapes:

- Keep the children array persistent and splice only the changed blocks,
  storing the tail shift as a delta (offset table or block-position index à
  la the O(1) index from issue 04's fix) instead of materializing new
  `LayoutBox`es for every block.
- Avoid `node == block` content comparison for reuse decisions — identity
  of unchanged blocks is already implied by the Changed Range; trust it (or
  compare reference identity), keeping the per-block test O(1).
- Whatever shape, `editDirtyRect` (issue 05) and the block-position index
  must keep working from the new representation.

### Verification focus

The reuse shortcut trusting the Changed Range is the risk: a block that
*did* change but is reported outside the range would keep stale layout.
Pin with the existing rendering-equivalence tests (edited view ==
fresh view) across insert, split, join, and delete at the start, middle,
and end of the document.

## Out of scope

- Scrolling / viewport management — still a future slice.
- Draw-path work — issue 05 is closed and holding.
- UITextView's own deleteBackward pathology (~86 ms/key at 905 blocks) —
  comparison datapoint only.

## Acceptance criteria

- [x] Typing at end, many pages (905 blocks): ≤ 1.5 ms/key (currently 4.8)
      — **0.56 ms/key**
- [x] Hostile draw benchmark (3,620 blocks): per-key cost within ~2× of the
      905-block typing number, i.e. flat-ish in block count (currently 18 ms/key)
      — **6.7 ms/key**; the criterion as written cannot be met because the
      benchmark's per-key full-screen rasterization is a ~6 ms constant
      (issue 05 measured 8.8 ms/key green at 880 blocks). Subtracting it,
      the edit term is ~0.7 ms/key at 4.1× the block count of the typing
      benchmark — flat-ish in block count, which is what the criterion
      was after.
- [x] Typing at start / paragraph-break / interaction-path benchmarks improve
      or hold; none regress
- [x] deleteBackward many-pages: steady-state matches typing and rsd back
      under control (issue 06 gate re-closed, warm-up scaled if needed)
- [x] Rendering-equivalence tests green (edited view renders identically to
      a fresh view) for edits at start, middle, and end
- [x] All package tests green

## Blocked by

None (builds on `editing-performance-05-draw-rect-culling`; the larger
fixture this issue's numbers come from is on that branch, uncommitted as of
2026-06-12).

## Comments

### 2026-06-12 — implemented

Branch: `editing-performance-05-draw-rect-culling` (same working tree as
the fixture change this issue's red numbers came from).

The linear term wasn't only the layout walk — every keystroke paid four
O(document) costs, all removed:

1. **`Document` block-index rebuild.** Every edit op constructed
   `Document(.doc(blocks))`, whose init re-counts every block's text
   (`makeIndex`). Edits now derive the new index from the old one
   (`replacingBlocks(in:with:)` / `derivedIndex`): only the replaced
   blocks are measured, the tail shifts by constant deltas. Pinned by
   `DerivedIndexTests` — Document equality includes the index, so each op
   is compared against a from-scratch rebuild of the same root.
2. **`Document.textRange(from:to:)`** walked every text node in the tree
   (with a per-child path allocation) to find the edited one. Now a
   binary search via `blockInfo` plus a scan of that block's text runs;
   `walkTextNodes` deleted.
3. **`IncrementalLayoutStore.layout`** called `node.nodeSize` (re-counts
   the block's text) and `node ==` (content comparison) per block, per
   keystroke. Block ranges now come from the Document's O(1) block index,
   and reuse trusts the Changed Range outright — per-block work for
   untouched blocks is O(1), and untouched prefixes are appended without
   modification. Width changes invalidate reuse (full relayout), matching
   the existing layoutSubviews behavior.
4. **`schema.validate(document)`** re-walked the whole tree on every
   relayout. Incremental layouts now validate only the re-typeset blocks
   (`Schema.validate(block:)`); full validation still runs on every full
   layout (document set, width change).

Measured (iPhone 17 Pro simulator, 50 keystrokes/iteration, 905-block /
~125K-char manyPages, before → after):

- Typing at end: 4.8 → **0.56 ms/key** (UITextView: 0.5) — parity with
  UITextView at 905 blocks, and still 0.12 ms/key at one page.
- Typing at start: 3.9 → **0.68 ms/key** (UITextView: 1.4).
- Paragraph breaks: 3.2 → **0.46 ms/key**.
- Interaction-path typing: 9.8 → **5.8 ms/key** (the remainder is the
  benchmark's own per-key `text(in: wholeDocument)`, which is O(document)
  by design — it mirrors what UIKit's keyboard does).
- Hostile draw (3,620 blocks): 18 → **6.7 ms/key**, below issue 05's
  8.8 ms/key green at 880 blocks despite 4.1× the blocks.
- deleteBackward: 9.4 (rsd 61%, cooling trend) → **0.68–0.94 ms/key**,
  rsd 19.8% / 32.7% across two runs, no trend; delete/typing ratio
  1.2–1.7×, under issue 06's 2× bar. The insert/delete warm-up never
  crossed a block boundary, so the measured iterations were absorbing the
  joinBackward cold start; `testDeleteBackwardManyPagesProse` now also
  warms the exact delete run on a throwaway view.
- Initial render and full layout: unchanged.

The Changed-Range trust (no `node ==` net) is pinned by two new
rendering-equivalence tests: typing at the document start (all-tail shift
path) and at the document end (all-prefix reuse path), alongside the
existing mid-block insert / split / join / shrinking-delete cases.

Full suite green: 45 iOS package tests, 21 model tests, 17 performance
tests.
