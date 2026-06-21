# y-prosemirror v1.x encoding contract (the Shared Replica wire format)

Reference spec for the **Binding** ([ADR 0012]). Source: `y-prosemirror@v1.3.7`,
`src/plugins/sync-plugin.js` and `src/lib.js`. This is the exact shape a ProseKit
peer and a browser Tiptap peer must both produce in the **Shared Replica**, proven
by interop fixtures. Read it as the encoding ProseKit must match — not as code to
admire.

## Top-level

- The document is a single `Y.XmlFragment`, stored under a **field name** on the
  `YDoc` (`ydoc.get(name, Y.XmlFragment)`). y-prosemirror's own default is
  `"prosemirror"`; **Tiptap's `Collaboration` extension defaults to `"default"`.**
  This field name must match the JS peer exactly or the two bind to different
  fragments and never converge. **Confirm the peer's name before writing fixtures.**
- Fragment children are block `Y.XmlElement`s; the PM `doc` top node itself is *not*
  represented — it's the fragment.

## Block Node → `Y.XmlElement`  (`createTypeFromElementNode`, lib.js ll. 414–427)

- `nodeName` = the **Schema** type name (`paragraph`, `heading`, `bulletList`,
  `codeBlock`, …). Read back via `el.nodeName`.
- **Attrs** → one `el.setAttribute(key, val)` per attr where `val !== null` and
  `key !== "ychange"`. Values are stored as their JSON value (string/number/object),
  not stringified. Read back via `el.getAttributes()`. A `null` attr is *absent*,
  not stored — so ProseKit must treat "absent" and "null" as equal on both sides.
- Children inserted in order; a run of adjacent inline text nodes is coalesced into
  **one** `Y.XmlText` (see below), block children stay separate elements.

## Inline text → `Y.XmlText`  (`createTypeFromTextNodes`, `normalizePNodeContent`)

- `normalizePNodeContent` groups **consecutive** PM text nodes into a single array →
  a single `Y.XmlText`. Non-text children break the run. So one `Y.XmlText` can hold
  many differently-marked spans; it is *not* one-XmlText-per-PM-text-node.
- The `Y.XmlText` content is a Yjs **delta**: each PM text node →
  `{ insert: node.text, attributes: marksToAttributes(node.marks) }`.
- Read back (`createTextNodesFromYText`): `text.toDelta()` → for each op,
  `schema.text(op.insert, attributesToMarks(op.attributes))`.

## Marks → `Y.XmlText` formatting attributes  (`marksToAttributes` ll. 1121–1130)

This is the subtle part.

- **Non-overlapping mark** (the common case): key = `mark.type.name`, value =
  `mark.attrs` (an object; `{}` when the mark has no attrs). E.g. `bold → { bold: {} }`,
  `link → { link: { href, target } }`.
- **Overlapping mark** (`!mark.type.excludes(mark.type)` — a mark type that does
  *not* exclude another of its own kind, e.g. multiple comments): key =
  `` `${mark.type.name}--${hashOfJSON(mark.toJSON())}` ``, value = `mark.attrs`. The
  hash disambiguates two same-type marks on the same span.
- On read, `yattr2markname` strips a trailing `--XXXXXXXX` (8 base64 chars) to
  recover the mark name; the mark is rebuilt as `schema.mark(name, attrs)`.
- `ychange` is reserved (snapshot diff rendering) — never emit it, skip it on read.

### The hash is the one hard-to-replicate corner

`hashOfJSON = base64(convolute(sha256(lib0.encodeAny(json))))` (`src/utils.js`). It
depends on **lib0's binary `encodeAny`** (not `JSON.stringify`), a custom byte
convolution, then sha256 + base64. Replicating it byte-exactly in Swift is real work.

**Scoping escape:** the hashed-key path is hit *only* for overlapping marks. The
standard Tiptap Simple-Editor mark set (bold, italic, strike, code, link, highlight,
underline, superscript) are all self-excluding → **plain mark names, hash never
needed.** So v1 implements only the plain-name path and asserts no overlapping marks
in the **Schema**. Defer `hashOfJSON` until/unless an overlapping mark (comments) is
added — and write it against an interop fixture when you do.

## Diff / identity  (`updateYFragment`, `equalYTypePNode`, `computeChildEqualityFactor`)

- PM→Y is a structural diff, not a rebuild. Children are matched by `nodeName`
  (`matchNodeName`) plus structural equality (`equalYTypePNode`: same name, equal
  attrs, recursively equal children / equal text+marks). Matched `Y.XmlElement`s are
  **mutated in place** (attrs patched, children recursed); unmatched ones are
  delete+insert. *Mutating-in-place is the correctness requirement* — recreating a
  matched element discards concurrent remote edits into it. This is ProseKit's
  `Node ⇄ Y` mapping job (Question 5 / **Binding**).
- `computeChildEqualityFactor` picks the best alignment of left/right runs to
  minimize delete+insert. ProseKit's equivalent diff need not match it op-for-op
  (Yjs converges regardless) but should match the *in-place vs replace* decision so
  structural equivalence with the JS peer holds.

## Positions  (`absolutePositionToRelativePosition` / inverse, lib.js ll. 54–193)

For **YRelativePosition** selection anchoring (Question 9): a flat PM/ProseKit
**Position** maps to a relative position by walking the fragment — each
`Y.XmlElement` contributes `nodeSize` (its mapped PM node size, i.e. content + 2 for
open/close tags), each `Y.XmlText` contributes its length. The mapping requires the
live `Node ⇄ Y` correspondence (the `nodeSize` lookups come from it). The inverse
sums the same sizes back to an absolute offset, minus 1 for the outer fragment tag.

## v1 checklist (tracer-bullet order)

1. Fragment field name agreed with the JS peer; single paragraph of plain text
   round-trips ProseKit ⇄ browser over Hocuspocus.
2. Marks (plain-name path only) on text spans.
3. Block types + attrs (`heading.level`, `link.href`, `textAlign`).
4. Nesting / lists (coalesced text runs, nested elements).
5. Opaque round-trip: unknown `nodeName` / unknown mark key preserved, never dropped
   ([ADR 0006] — convergence-critical).

Deferred: `hashOfJSON` overlapping-mark keys; `ychange`/snapshot rendering.

[ADR 0012]: ../adr/0012-collaboration-targets-cross-platform-y-prosemirror.md
[ADR 0006]: ../adr/0006-unknown-node-types-preserved-as-opaque-content.md
