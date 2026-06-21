# Implementation plan: Yjs collaboration binding (`ProseKitYjs`)

Build a Yjs-backed collaborative editor for ProseKit, modeled on y-prosemirror,
using SwiftYrs. This plan turns the captured design into sequenced, testable work.

## Source documents

- Glossary & authority model — [CONTEXT.md](../../CONTEXT.md) (Collaboration section:
  Convergence Authority, Shared Replica, Binding, Join, Decoration)
- [ADR 0011 — YDoc is the convergence authority](../adr/0011-ydoc-is-the-convergence-authority.md)
- [ADR 0012 — cross-platform y-prosemirror convergence](../adr/0012-collaboration-targets-cross-platform-y-prosemirror.md)
- [ADR 0010 — collaborative undo delegates to YUndoManager](../adr/0010-collaborative-undo-delegates-to-yundomanager.md)
- [ADR 0006 — unknown node types preserved as opaque content](../adr/0006-unknown-node-types-preserved-as-opaque-content.md)
- [ADR 0004 — step-based history](../adr/0004-step-based-history-not-nsundomanager.md) (qualified by 0010 for collab)
- [ADR 0003 — Tiptap JSON is the native format](../adr/0003-tiptap-json-is-the-native-format.md) (pays the schema-parity cost)
- **Wire format spec** — [y-prosemirror v1.x encoding contract](../research/2026-06-21-y-prosemirror-encoding-contract.md)
- Reference implementation — `y-prosemirror@v1.3.7` `src/plugins/sync-plugin.js`, `src/lib.js`

## Architecture recap (what we're building)

- A new SwiftPM target **`ProseKitYjs`** depending on `ProseEditor` + `SwiftYrs`.
  `ProseModel`/`ProseEditor` stay Yjs-free; collaboration is opt-in.
- A thin, Yjs-agnostic **observer seam** on `EditorCore`: outbound
  `didApplyTransaction`, inbound `applyRemote`.
- The **Binding** owns the `YDoc` on the MainActor (the single serialization owner
  SwiftYrs' `@unchecked Sendable` contract requires), tags its own writes with an
  origin to break the echo loop, and keeps `Document` ⇄ `Shared Replica` equal:
  - **PM→Y**: port `updateYFragment` — structural diff, matched subtrees mutated in
    place (never recreated), driven by a position-keyed `Node ⇄ Y` correspondence.
  - **Y→PM**: translate Y events into targeted `remote`-Origin `Step`s (protects
    incremental layout via `changedRange`).
- Selection survives remote edits via `YRelativePosition` (capture-at-apply).
- Remote cursors render as Selection Layer chrome (no decoration engine), from
  `YAwareness`, in v1.
- Provider-agnostic; convergence proven against Hocuspocus + a browser Tiptap peer.

## Phase 0 — Scaffolding & the EditorCore seam

Goal: the plumbing exists, no behavior yet.

1. Add SwiftYrs dependency to [Package.swift](../../Package.swift) (local
   `path: "../SwiftYrs"` for dev; pin to `siuying/SwiftYrs` tag for release) and a
   `ProseKitYjs` target depending on `ProseEditor` + `SwiftYrs`, plus a
   `ProseKitYjsTests` target.
2. Add the `EditorCore` observer seam (keep it Yjs-agnostic — `EditorCore` must not
   import SwiftYrs):
   - `didApplyTransaction: ((AppliedTransaction) -> Void)?` (or an `AsyncStream`),
     fired after `state` is updated in every `dispatch` path (typing, commands,
     undo/redo, remote).
   - `applyRemote(_ transaction: Transaction)` — dispatches a `.remote`-origin
     transaction (history already gates on `origin == .local`, so this is mostly
     free) and triggers `relayout(changedRange:)`.
3. Verify `EditorCore`'s existing paths all route through one notification point so
   the Binding sees every change exactly once.

Acceptance: `ProseKitYjs` builds and links SwiftYrs; a unit test observes
`didApplyTransaction` firing for a local edit and `applyRemote` mutating state with
`.remote` origin and no history entry.

## Phase 1 — Tracer bullet (the riskiest integration, proven end to end)

Goal: a **single plain-text paragraph** converges live, ProseKit ⇄ browser
y-prosemirror, over Hocuspocus. No marks, no block variety.

1. `YBinding` skeleton: owns a `YDoc` + `YXmlFragment` (field name **must** match the
   peer — confirm `"default"` for Tiptap vs `"prosemirror"`; assert it), MainActor-confined.
2. Minimal **encoder** (PM→Y) for `doc > paragraph > text`: build/patch a single
   `YXmlElement("paragraph")` containing one `YXmlText`, writing via
   `write(origin: bindingOrigin)`.
3. Minimal **decoder** (Y→PM): observe the fragment; on remote change (origin ≠
   bindingOrigin), produce a `remote` `Transaction` of `ReplaceStep`s and
   `applyRemote`.
4. **Join** gate: subscribe to the provider's synced signal (`HocuspocusProvider.isSynced`);
   seed-from-Document iff empty replica, else reset Document from the Y render.
5. **Selection survival**: capture caret as `YRelativePosition` before applying a
   remote change, resolve back after (see contract §Positions).
6. Loop-break verified: a local write does not re-trigger a self-apply.

Acceptance: an [interop fixture](../research/2026-06-21-y-prosemirror-encoding-contract.md)
where a Node `y-hocuspocus` server + browser Tiptap client and a ProseKit client
type into the same paragraph and both converge to identical text; caret stays put
when the remote inserts before it.

## Phase 1b — Awareness & remote cursors (Selection Layer)

Goal: presence ships with v1. Remote carets render as **Selection Layer chrome**
(Question 10 → A), reusing the geometry path that already draws the local caret.
Depends only on remote-apply + `YRelativePosition` (both from Phase 1) and the
existing `geometryMapper` — not on schema breadth, so it can land right after the
tracer bullet.

1. Broadcast local awareness: encode the local Selection as `YRelativePosition`
   anchor(s) + a `user` field (name, color) into `YAwareness`; update on selection
   change.
2. Receive remote awareness states; resolve each peer's relative positions back to
   ProseKit `Position`s via the `Node ⇄ Y` mapping.
3. Extend the **Selection Layer** to paint N remote carets + range highlights via
   `geometryMapper.caretRect` / `selectionRects`, colored/labeled per peer. Remote
   carets are editor-drawn overlays on *both* iOS and macOS (the system only knows
   the local caret).
4. Lifecycle: clear a peer's chrome on disconnect / awareness timeout.

Acceptance: two clients (ProseKit + browser Tiptap) show each other's live caret
and selection, correctly positioned as text is edited, and a peer's caret
disappears when it leaves.

## Phase 2 — Marks (plain-name path only)

1. `marksToAttributes` / `attributesToMarks` for **non-overlapping** marks: key =
   mark type name, value = mark attrs (`{}` when none). Map ProseKit `Mark` ⇄ Yjs
   `YXmlText` formatting per the contract §Marks.
2. Assert the Schema has **no overlapping (self-non-excluding) marks**; the
   `hashOfJSON` hashed-key path stays deferred.
3. Text-run coalescing: a run of adjacent marked spans is one `YXmlText`
   (`normalizePNodeContent` semantics).

Acceptance: bold/italic/strike/code/link/highlight/underline/superscript round-trip
against the browser peer; overlapping/`ychange` keys received from a richer peer are
preserved opaquely, not interpreted.

## Phase 3 — Block types & attrs

1. `YXmlElement.nodeName` ⇄ Schema type for all flat block types (heading,
   blockquote, codeBlock, …).
2. Attrs: `setAttribute(key, val)` for non-null, non-`ychange` attrs; treat
   absent == null on both sides (`heading.level`, `link.href`, `textAlign`).
3. Extend the encoder/decoder diff to handle block type changes (delete+insert vs
   in-place per `equalYTypePNode`).

Acceptance: heading-level changes, block-type toggles, and attr edits converge both
directions against the peer.

## Phase 4 — Nesting & lists

1. Recursive `updateYFragment` port for nested containers (lists, list items,
   nested blocks); `Node ⇄ Y` mapping carried across each `Mapping`, re-diffing only
   the `changedRange`.
2. `computeChildEqualityFactor`-equivalent alignment so the in-place-vs-replace
   decision matches the JS peer (structural equivalence, not op-for-op).

Acceptance: bulletList/orderedList/taskList with nested items converge; reordering
and nesting changes preserve concurrent edits into untouched siblings.

## Phase 5 — Opaque round-trip (convergence-critical, [ADR 0006])

1. Unknown `nodeName` → **Opaque Node**; unknown mark keys preserved on the text.
2. The encoder must **never drop** an element/mark it doesn't recognize — dropping
   deletes it from the Shared Replica for every peer.

Acceptance: a node type only the browser peer understands survives a full ProseKit
edit-and-sync cycle byte-faithfully; an interop fixture asserts no data loss.

## Phase 6 — v1 hardening

- Large initial-sync handled at Join time (apply before interactive / chunk) to
  avoid main-thread jank; profile per the editing-performance research discipline.
- Reconnect / offline-edit-then-rejoin convergence fixtures.
- **Undo in collab mode is disabled** (deliberate cut, not silently wrong) until v1.1.

## v1.1 — Collaborative undo ([ADR 0010])

Wire undo/redo to a `YUndoManager` scoped to the local origin; reconcile typing
coalescing with Y's capture-stop grouping; route the `NSUndoManager` bridge into the
active stack. Solo mode keeps the step-based stack ([ADR 0004]).

## Not in scope

No general **Decoration** engine. Remote cursors render as Selection Layer chrome
(Phase 1b), not as decorations. A reusable decoration system (for search
highlights, spellcheck, etc.) remains a possible future generalization that remote
cursors could migrate onto — but it is not built for v1 and nothing here depends on
it. Revisit with an ADR only if a feature actually needs model-positioned
presentation beyond selection chrome.

## Testing strategy

- **Interop fixtures** are the authority for every wire-format row (contract doc),
  run against a real browser Tiptap + `y-hocuspocus` peer — not Swift-only roundtrips.
- Swift unit tests for the seam, the `Node ⇄ Y` mapping, position translation, and
  loop-breaking.
- A convergence property test: random concurrent edit sequences applied to two
  bindings converge to identical `Document`s.

## Risks & open items

- **Fragment field-name mismatch** silently prevents convergence — confirm and
  assert first (contract §Top-level).
- **`hashOfJSON`** (overlapping marks) is hard to match byte-exactly; kept out of v1
  by the no-overlapping-marks assertion.
- **Main-thread jank** on large updates — Join-time / profiling concern, escalate to
  an off-main `YDoc` actor only if measured.
- Confirm SwiftYrs surfaces a `YRelativePosition` API sufficient for capture/resolve
  against a `YXmlText` index, and a `YAwareness` API (local-state set + remote-state
  observe) sufficient for the v1 cursor phase.
