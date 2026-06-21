# ProseKit

A native iOS rich-text editor built on a custom CoreText layout engine over a
ProseMirror-style document model. The document tree is the authority the layout
projects from; the rendered layout is a projection of it, never the other way
around. When collaboration is active a shared CRDT replica becomes the
*convergence* authority across peers: the binding keeps it equal to the Document,
and on divergence the replica reconciles into the Document via a `remote`-Origin
Transaction (see **Convergence Authority** under Collaboration).

## Language

### Document model

**Document**:
The root **Node** of the editable content; an immutable, persistent tree. Editing
produces a new Document rather than mutating in place.
_Avoid_: buffer, text storage, string

**Node**:
A single element in the Document tree. A Node is either a **Block Node** (lays out
vertically: paragraph, heading, blockquote, code block, list, list item) or an
**Inline Node** (flows within a line; today only text). Carries a type, **Attrs**,
and either child Nodes or, for text, a string + **Marks**.
_Avoid_: element, tag

**Mark**:
A piece of inline formatting attached to a text Node (bold, italic, code, link).
Marks are a set, not a tree; they describe a span's styling, not its structure.
_Avoid_: attribute (that's Attrs), style, format

**Attrs**:
Typed parameters on a Node (e.g. a heading's `level`, a link Mark's `href`).
Distinct from **Marks**: Attrs parameterize one Node; Marks are inline formatting.
_Avoid_: properties, options

**Position**:
An integer offset into the *flattened* Document, ProseMirror-style: every Node
boundary counts as a token, so positions can address both inside text and between
Nodes. The single addressing scheme for selection, steps, and decorations.
_Avoid_: index, offset (when ambiguous), caret (that's the Selection's focus)

**Step**:
The smallest first-class, invertible, serializable change to a Document (e.g.
`ReplaceStep`, `AddMarkStep`). Applying a Step to a Document yields a new Document.
_Avoid_: edit, mutation, operation, command (a Command produces Steps)

**Slice**:
A contiguous fragment of a **Document** cut between two **Positions**, carrying
its content plus how deeply its start and end are open (cut mid-Node), so it can
be fitted into another place in a Document. The unit of copy/paste and of
replace-range edits.
_Avoid_: snippet, fragment (a Slice's content is a fragment; the Slice also
carries the open depths), clipboard contents

**Transaction**:
An ordered batch of **Steps** applied atomically, plus the resulting Selection.
The only sanctioned way to change the editor's Document.
_Avoid_: edit, change, commit

**Mapping**:
The function that remaps a **Position** across one or more **Steps**, so selections,
decorations, and remote/undo positions survive edits.
_Avoid_: offset adjustment, rebase (rebase is a higher-level use of Mapping)

**Changed Range**:
The range of **Positions** in the resulting Document that a **Transaction**
touched: the union of its Steps' affected ranges, each carried forward through
the later Steps via **Mapping**. Consumers (layout, decorations) treat
everything outside it as untouched.
_Avoid_: dirty range, invalidation range (those are layout-side reactions to it)

**Selection**:
The current caret/range, expressed in **Positions**. A protocol; today only
`TextSelection` (an anchor Position and a head Position; collapsed = caret) exists.
`NodeSelection`/`GapCursor` arrive with the Nodes that need them.
_Avoid_: cursor (that's the collapsed case), range

**Origin**:
A tag every **Transaction** carries identifying who produced it — local, remote,
history (undo/redo). Lets observers and the history Extension distinguish edits;
the seam that keeps future collaboration tractable without inverting authority.
_Avoid_: source, author

**History**:
The undo/redo record: a stack of undo entries, each holding the inverted
**Steps** of one or more coalesced **Transactions**. Replaying an entry
produces a Transaction tagged with the history **Origin**; entries are carried
forward across later edits via **Mapping**.
_Avoid_: undo manager (that's the system bridge, not the record), undo stack

**Opaque Node**:
A **Node** whose type the editor doesn't understand but preserves: rendered as
a placeholder, selected and deleted only as a whole, and exported byte-faithful
to how it arrived. The guarantee that unsupported content survives a round trip.
Under collaboration this sharpens from a rendering nicety into a *convergence*
requirement: if the **Binding** drops an unrecognized type from the **Shared
Replica**, it deletes that content for *every* peer, not just locally — so opaque
round-tripping is mandatory wherever the replica is the **Convergence Authority**.
_Avoid_: unknown node (that's its cause, not its behavior), unsupported content
(that's the rendering)

**Schema**:
The declared, extensible set of Node types and Mark types and their rules (which
Nodes may contain which). The Document must conform to its Schema.
_Avoid_: grammar, model (Schema is the model's *definition*)

**Extension**:
The unit of configuration and extensibility (Tiptap-style). One Extension may
contribute Node/Mark specs to the **Schema**, **Commands**, keymap entries, input
rules, and **Render Hooks**. The editor is configured by an ordered list of
Extensions; built-in features are authored through the same API as third-party ones.
_Not yet built_: the Extension type itself; today Schema rules, Commands, and
keymap entries are wired directly, not contributed through an Extension.
_Avoid_: plugin (reserved for a future PM-style runtime plugin), module, feature

**Render Hook**:
The part of an **Extension** that turns model into pixels: a Mark's hook maps it to
CoreText attributes; a Block Node's hook maps it to a **Layout Box**. The custom
CoreText engine's replacement for ProseMirror's DOM serialization.
_Avoid_: toDOM, nodeView, renderer

**Input Rule**:
A pattern watched at the caret during typing that, on match, rewrites the
just-typed text into structure or formatting (e.g. `# ` becomes a heading).
Backspace immediately after a match reverts it to the literal text.
_Avoid_: autocorrect, autoformat, markdown shortcut (that's one family of them)

**Command**:
A pure function `(state, dispatch?) -> Bool` that, given the editor state, optionally
produces and dispatches a **Transaction**. Commands are how intents (toggle bold,
split block) are expressed and composed.
_Avoid_: action, step (a Command produces Steps), handler

### Collaboration

**Convergence Authority**:
The shared CRDT replica that all peers' edits flow into and that, by CRDT merge,
is the single state every peer agrees on. It does not displace the **Document** as
the layout-projection authority; the two are kept equal by the binding, and on
divergence the replica wins and reconciles into the Document through a
`remote`-**Origin** **Transaction**. Active only in collaboration.
_Avoid_: source of truth (ambiguous — the Document is still what layout reads),
server, master copy

**Shared Replica**:
The Yjs document that is the **Convergence Authority**. Its structure is *not* a
free choice: ProseKit must encode the **Document** into it exactly as
`y-prosemirror` does — a top-level XML fragment, **Block Nodes** as XML elements
named by their **Schema** type, **Attrs** as element attributes, and text as XML
text whose **Marks** are formatting attributes. This makes the y-prosemirror XML
encoding a binding *contract* a ProseKit peer and a JS Tiptap peer both implement,
proven by **Interop Fixtures**. Distinct from Tiptap-JSON round-trip ([ADR 0003]):
JSON is a load/export format, the Shared Replica is live convergence. The encoding
target is y-prosemirror **v1.x** (classic `updateYFragment`); newer
`y-attributed-*` formatting from richer JS peers is preserved opaquely, not
interpreted.
_Avoid_: the document JSON, Tiptap export, snapshot

**Binding**:
The component that keeps the **Document** and the **Shared Replica** equal in both
directions. Local **Transaction**s diff into the replica (matched subtrees mutated
in place, never recreated, to preserve concurrent remote edits); remote replica
changes translate into `remote`-**Origin** **Transaction**s of targeted **Step**s.
It maintains a position-keyed **Node** ⇄ Y-type correspondence carried across each
Transaction's **Mapping**, re-diffing only the **Changed Range**. It owns the
**Shared Replica** on the editor's actor (MainActor) — the single serialization
owner the CRDT handle requires — and tags its own writes with an origin so the
replica observer skips them, breaking the echo loop.
_Avoid_: sync engine, adapter, provider (a **Provider** moves bytes between peers;
the Binding maps between the two in-process representations)

**Join**:
A peer attaching to a collaborative document. Seeding is decided only *after* the
**Provider** signals initial sync: an empty **Shared Replica** is seeded from the
current **Document**; a non-empty replica replaces the Document via a
`remote`-**Origin** **Transaction**. A Document handed to the editor is therefore
discarded when joining a populated replica — that is collaborative semantics, not
data loss; seed content belongs to *creating* a document, not *joining* one.
_Avoid_: load, open, connect (connecting is the Provider's job; the Join is the
seeding decision that follows the synced signal)

### Layout

**Layout Box**:
The atomic unit the CoreText engine stacks. A *leaf* Layout Box wraps one leaf
Block Node and typesets it via CoreText into **Line Fragments**; a *container*
Layout Box stacks child boxes vertically and draws decorations (indent bars,
bullets, backgrounds). The layout tree mirrors the Document tree's block structure.
_Avoid_: cell, view, line (a Layout Box is not a Runestone "line")

**Line Fragment**:
One visually-wrapped line produced by CoreText within a leaf Layout Box. A long
paragraph Block Node yields many Line Fragments.
_Avoid_: line, row

**Viewport**:
The currently visible window onto the laid-out Document, expressed in content
coordinates. Scrolling moves the Viewport over the layout; it never moves or
re-lays-out the Document. Layout exists for every Block Node whether or not
the Viewport can see it.
_Avoid_: visible rect, screen, window

**Canvas**:
The paint surface that draws the **Layout Boxes** intersecting the **Viewport**.
The Canvas holds no document or geometry authority — it is repainted from the
layout tree and answers no questions; caret, selection, and hit-testing geometry
are answered in content coordinates, never Canvas coordinates.
_Avoid_: content view, backing store, layer

**Selection Layer**:
The chrome that renders the **Selection** — the blinking caret and the
range highlight — sitting above the **Canvas**, never inside it. One role,
two platform realizations: on iOS it *is* the system (`UITextInteraction`
draws caret, handles, loupe, menu); on macOS it is an editor-owned overlay
that draws caret and highlight itself, since AppKit's text-input protocol
draws no chrome. Reads geometry in content coordinates like everything else;
the **Canvas** stays authority-free on both platforms. In collaboration it also
renders each remote peer's caret and range highlight — sourced from awareness,
anchored by **YRelativePosition**, colored and labeled per peer. Remote carets are
editor-drawn overlays on *both* platforms (the system only ever knows the local
caret). ProseKit has no general decoration system; remote carets are selection
chrome, drawn through the same geometry mapper as the local Selection.
_Avoid_: caret view, cursor layer, selection view (it is the whole chrome,
not one piece)
