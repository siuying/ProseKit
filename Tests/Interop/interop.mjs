// Headless y-prosemirror peer for ProseKitYjs interop tests.
//
// Runs the *real* y-prosemirror library (the same code Tiptap drives in the
// browser) over a plain Node process — no DOM required, because the encode /
// decode helpers operate on the Yjs document directly. The wire bytes are the
// standard Yjs v1 update protocol, which the Swift SwiftYrs peer speaks too, so
// converging here is a genuine cross-implementation convergence proof.
//
// Modes:
//   fragment                  Print the root XML-fragment field name the peer
//                             keys the shared type on ("prosemirror").
//   encode <text> <outFile>   Build doc>paragraph>text(text) as a y-prosemirror
//                             Y.Doc on fragment "prosemirror" and write its v1
//                             update bytes to <outFile>. (JS -> Swift)
//   decode <inFile>           Apply a v1 update produced by the Swift peer and
//                             print the plain text y-prosemirror decodes from
//                             the "prosemirror" fragment. (Swift -> JS)
//   encodeJSON <json> <out>   Like `encode` but for a full ProseMirror doc JSON
//                             (marks/blocks/nesting). (JS -> Swift)
//   decodeJSON <inFile>       Like `decode` but prints the full doc JSON the JS
//                             peer sees (so Swift can assert marks/attrs). (Swift -> JS)
//   mutateJSON <base> <new> <out>
//                             Reconcile the replica from <base> to doc <new> via
//                             y-prosemirror's in-place `updateYFragment`, so a
//                             structural edit merges with a peer's concurrent
//                             edit. Emits the merged v1 update. (JS structural op)

import { readFileSync, writeFileSync } from "node:fs";
import * as Y from "yjs";
import { Schema } from "prosemirror-model";
import { prosemirrorToYDoc, yDocToProsemirrorJSON, updateYFragment } from "y-prosemirror";

const FRAGMENT = "prosemirror";

// doc > paragraph > text, plus the marks the marks slice converges. Each mark's
// attrs mirror ProseKit's exactly (link → {href}, highlight → {color}, the rest
// attr-less) so the formatting attributes both peers write to the YXmlText match
// byte-for-byte.
const schema = new Schema({
  nodes: {
    doc: { content: "block+" },
    paragraph: { group: "block", content: "text*", attrs: { textAlign: { default: null } }, toDOM: () => ["p", 0] },
    heading: {
      group: "block",
      content: "text*",
      attrs: { level: { default: 1 }, textAlign: { default: null } },
      toDOM: (node) => [`h${node.attrs.level}`, 0],
    },
    blockquote: { group: "block", content: "block+", toDOM: () => ["blockquote", 0] },
    // A code block: a node type ProseKit's Schema does not know, so it converges
    // via the opaque path (#70) — ProseKit must preserve it byte-faithfully.
    codeBlock: { group: "block", content: "text*", marks: "", code: true, toDOM: () => ["pre", ["code", 0]] },
    // An atom node ProseKit's Schema does not know — used to prove opaque
    // round-trip (#70): ProseKit must preserve it byte-faithfully.
    image: { group: "block", atom: true, attrs: { src: {} }, toDOM: (node) => ["img", { src: node.attrs.src }] },
    // `listItem`/`taskItem` allow a trailing nested list so nesting fixtures
    // (a list inside a list item) parse on the JS peer exactly as ProseKit nests.
    bulletList: { group: "block", content: "listItem+", toDOM: () => ["ul", 0] },
    orderedList: { group: "block", content: "listItem+", attrs: { start: { default: 1 } }, toDOM: () => ["ol", 0] },
    listItem: { content: "paragraph block*", toDOM: () => ["li", 0] },
    taskList: { group: "block", content: "taskItem+", toDOM: () => ["ul", 0] },
    taskItem: { content: "paragraph block*", attrs: { checked: { default: false } }, toDOM: () => ["li", 0] },
    text: {},
  },
  marks: {
    bold: { toDOM: () => ["strong", 0] },
    italic: { toDOM: () => ["em", 0] },
    strike: { toDOM: () => ["s", 0] },
    code: { toDOM: () => ["code", 0] },
    underline: { toDOM: () => ["u", 0] },
    superscript: { toDOM: () => ["sup", 0] },
    subscript: { toDOM: () => ["sub", 0] },
    link: {
      attrs: { href: {} },
      toDOM: (mark) => ["a", { href: mark.attrs.href }, 0],
    },
    highlight: {
      attrs: { color: {} },
      toDOM: (mark) => ["mark", { "data-color": mark.attrs.color }, 0],
    },
    // A mark key only the JS peer understands — proves opaque *mark* round-trip
    // (#70): ProseKit carries it through an edit-and-sync cycle without loss.
    comment: {
      attrs: { id: {} },
      toDOM: (mark) => ["span", { "data-comment": mark.attrs.id }, 0],
    },
  },
});

function paragraphDoc(text) {
  const content = text.length ? [schema.text(text)] : [];
  return schema.node("doc", null, [schema.node("paragraph", null, content)]);
}

function plainText(json) {
  const paragraph = (json.content ?? [])[0];
  const textNode = (paragraph?.content ?? [])[0];
  return textNode?.text ?? "";
}

const [mode, ...rest] = process.argv.slice(2);

if (mode === "fragment") {
  // Print the root XML-fragment field name the JS peer keys the shared type on.
  // The Swift side asserts YBinding.defaultFragmentName matches this, so a
  // rename on either peer fails loudly instead of silently never converging.
  process.stdout.write(FRAGMENT);
} else if (mode === "encode") {
  const [text, outFile] = rest;
  const ydoc = prosemirrorToYDoc(paragraphDoc(text), FRAGMENT);
  writeFileSync(outFile, Buffer.from(Y.encodeStateAsUpdate(ydoc)));
} else if (mode === "decode") {
  const [inFile] = rest;
  const ydoc = new Y.Doc();
  Y.applyUpdate(ydoc, new Uint8Array(readFileSync(inFile)));
  process.stdout.write(plainText(yDocToProsemirrorJSON(ydoc, FRAGMENT)));
} else if (mode === "encodeJSON") {
  // <jsonFile> holds a full ProseMirror doc JSON (marks included). Build it as a
  // y-prosemirror Y.Doc and write the v1 update bytes. (JS -> Swift)
  const [jsonFile, outFile] = rest;
  const docJSON = JSON.parse(readFileSync(jsonFile, "utf8"));
  const ydoc = prosemirrorToYDoc(schema.nodeFromJSON(docJSON), FRAGMENT);
  writeFileSync(outFile, Buffer.from(Y.encodeStateAsUpdate(ydoc)));
} else if (mode === "mutateJSON") {
  // Reconcile the shared replica from <baseFile> to the full ProseMirror doc in
  // <newDocFile> using y-prosemirror's *real* in-place reconciler
  // (`updateYFragment`) — the same code path the browser binding runs on every
  // transaction. Structural edits (reorder, nest) land as minimal CRDT ops that
  // merge with a peer's concurrent edit into untouched siblings, rather than a
  // wholesale delete+reinsert that would clobber it. Emits the merged v1 update.
  const [baseFile, newDocFile, outFile] = rest;
  const ydoc = new Y.Doc();
  Y.applyUpdate(ydoc, new Uint8Array(readFileSync(baseFile)));
  const yFragment = ydoc.getXmlFragment(FRAGMENT);
  const newDoc = schema.nodeFromJSON(JSON.parse(readFileSync(newDocFile, "utf8")));
  ydoc.transact(() => {
    updateYFragment(ydoc, yFragment, newDoc, { mapping: new Map() });
  });
  writeFileSync(outFile, Buffer.from(Y.encodeStateAsUpdate(ydoc)));
} else if (mode === "decodeJSON") {
  // Apply a Swift-produced update and print the full ProseMirror doc JSON
  // y-prosemirror decodes, so the Swift side can assert marks. (Swift -> JS)
  const [inFile] = rest;
  const ydoc = new Y.Doc();
  Y.applyUpdate(ydoc, new Uint8Array(readFileSync(inFile)));
  process.stdout.write(JSON.stringify(yDocToProsemirrorJSON(ydoc, FRAGMENT)));
} else {
  process.stderr.write(`unknown mode: ${mode}\n`);
  process.exit(2);
}
