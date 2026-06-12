# Unknown node and mark types are preserved as opaque content

Tiptap documents may contain node types outside our supported set (e.g.
`image` from the Simple Editor's upload button). Extending ADR 0005 from attr
values to types: an unknown mark is kept in the model and rendered as plain
text; an unknown block node loads as an Opaque Node — rendered as a
placeholder, selectable and deletable as a unit, its JSON preserved verbatim
on export. Strict rejection was rejected because it breaks "Tiptap exports
load here" for real documents; stripping was rejected as silent data loss.
Phasing: unknown-mark preservation lands immediately; Opaque Node rendering
(which needs NodeSelection) is its own slice, with a clear load error as the
interim behavior — never silent stripping.
