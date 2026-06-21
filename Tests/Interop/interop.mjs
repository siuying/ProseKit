// Headless y-prosemirror peer for ProseKitYjs interop tests.
//
// Runs the *real* y-prosemirror library (the same code Tiptap drives in the
// browser) over a plain Node process — no DOM required, because the encode /
// decode helpers operate on the Yjs document directly. The wire bytes are the
// standard Yjs v1 update protocol, which the Swift SwiftYrs peer speaks too, so
// converging here is a genuine cross-implementation convergence proof.
//
// Modes:
//   encode <text> <outFile>   Build doc>paragraph>text(text) as a y-prosemirror
//                             Y.Doc on fragment "prosemirror" and write its v1
//                             update bytes to <outFile>. (JS -> Swift)
//   decode <inFile>           Apply a v1 update produced by the Swift peer and
//                             print the plain text y-prosemirror decodes from
//                             the "prosemirror" fragment. (Swift -> JS)

import { readFileSync, writeFileSync } from "node:fs";
import * as Y from "yjs";
import { Schema } from "prosemirror-model";
import { prosemirrorToYDoc, yDocToProsemirrorJSON } from "y-prosemirror";

const FRAGMENT = "prosemirror";

// doc > paragraph > text, plus the marks the marks slice converges. Each mark's
// attrs mirror ProseKit's exactly (link → {href}, highlight → {color}, the rest
// attr-less) so the formatting attributes both peers write to the YXmlText match
// byte-for-byte.
const schema = new Schema({
  nodes: {
    doc: { content: "paragraph+" },
    paragraph: { content: "text*", toDOM: () => ["p", 0] },
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

if (mode === "encode") {
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
