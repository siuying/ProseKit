# Prose

A native iOS rich-text editor built on a custom CoreText layout engine over a
ProseMirror-style document model. The document tree is the structural authority;
the rendered layout is a projection of it, never the other way around.

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

**Schema**:
The declared, extensible set of Node types and Mark types and their rules (which
Nodes may contain which). The Document must conform to its Schema.
_Avoid_: grammar, model (Schema is the model's *definition*)

**Extension**:
The unit of configuration and extensibility (Tiptap-style). One Extension may
contribute Node/Mark specs to the **Schema**, **Commands**, keymap entries, input
rules, and **Render Hooks**. The editor is configured by an ordered list of
Extensions; built-in features are authored through the same API as third-party ones.
_Avoid_: plugin (reserved for a future PM-style runtime plugin), module, feature

**Render Hook**:
The part of an **Extension** that turns model into pixels: a Mark's hook maps it to
CoreText attributes; a Block Node's hook maps it to a **Layout Box**. The custom
CoreText engine's replacement for ProseMirror's DOM serialization.
_Avoid_: toDOM, nodeView, renderer

**Command**:
A pure function `(state, dispatch?) -> Bool` that, given the editor state, optionally
produces and dispatches a **Transaction**. Commands are how intents (toggle bold,
split block) are expressed and composed.
_Avoid_: action, step (a Command produces Steps), handler

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
