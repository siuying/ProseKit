# Tiptap JSON is the native document format

Prose documents must interoperate with Tiptap (the JSON its Simple Editor
exports must load here, and vice versa). Rather than keeping our own schema
and maintaining a converter, the Schema adopts Tiptap's ProseMirror schema
verbatim: its node/mark type names (`bulletList`, `taskItem`, `codeBlock`,
`strike`, `highlight`, ...), its attrs shapes (`heading.level`, `link.href`,
`textAlign` as a block attr), and its nesting rules. Compatibility is
round-trip: we never introduce a node, mark, or attr shape that Tiptap's
Simple Editor set doesn't understand, so "compatible" is structural rather
than a converter to maintain.
