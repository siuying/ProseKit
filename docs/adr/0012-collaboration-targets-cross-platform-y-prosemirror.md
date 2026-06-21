---
status: accepted
---

# Collaboration targets cross-platform y-prosemirror convergence

Collaboration is designed so a ProseKit client and a browser Tiptap + y-prosemirror
client can edit the *same* Yjs document and converge — not merely so two Swift
peers can sync. This makes the y-prosemirror **v1.x** XML encoding a binding
*contract* ProseKit must implement faithfully (top-level `XmlFragment`, **Block
Nodes** as `XmlElement` named by **Schema** type, **Attrs** as element attributes,
text as `XmlText` with **Marks** as formatting attributes), proven by interop
fixtures against a real browser peer rather than Swift-only roundtrip tests. The
schema-parity cost this normally carries is already paid by [ADR 0003] (Tiptap's
ProseMirror schema verbatim).

## Considered Options

- **Swift-peer-only collaboration** — own both ends of the encoding, pick whatever
  shared-type layout is convenient. Simpler, but forecloses browser interop and the
  large existing Tiptap collaboration ecosystem. Rejected.
- **Cross-platform convergence with JS y-prosemirror** (chosen).

## Consequences

- The Binding's PM→Y direction ports y-prosemirror's `updateYFragment` rather than
  translating ProseKit `Step`s directly, because *structural equivalence with the
  JS peer* — not just eventual convergence — is what is on the line. (This absorbs
  the diff-with-mapping vs step-translation decision: diff-with-mapping wins because
  it is the algorithm validated against the reference.)
- **Opaque Node** round-tripping becomes a convergence-correctness requirement:
  dropping an unrecognized type deletes it from the **Shared Replica** for every
  peer (see [ADR 0006]).
- The encoding is hard to migrate once peers have stored documents, so the v1.x
  target and its fixtures are load-bearing.
- The interop proof runs against Hocuspocus + a browser peer; the Binding itself
  stays provider-agnostic.

[ADR 0003]: 0003-tiptap-json-is-the-native-format.md
[ADR 0006]: 0006-unknown-node-types-preserved-as-opaque-content.md
