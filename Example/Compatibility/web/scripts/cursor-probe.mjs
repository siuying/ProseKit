// Cursor interop probe: a headless web peer that (1) waits for a native peer
// to publish a y-prosemirror awareness cursor, and (2) publishes its own
// cursor anchored into the shared text, exactly as tiptap's
// CollaborationCursor would — so the native apps can draw a remote caret.
//
// Usage: node scripts/cursor-probe.mjs [--stay]
//   --stay  keep running (and keep the published cursor alive) after the
//           assertions pass, for screenshot sessions; Ctrl-C to quit.
import { HocuspocusProvider } from "@hocuspocus/provider";
import * as Y from "yjs";
import WebSocket from "ws";

const url = `ws://localhost:${process.env.PORT ?? 4321}/collaboration`;
const name = process.env.ROOM ?? "prosekit-compatibility";
const stay = process.argv.includes("--stay");

const document = new Y.Doc();
const provider = new HocuspocusProvider({
  url,
  name,
  document,
  WebSocketPolyfill: WebSocket,
});

await new Promise((resolve) => provider.on("synced", resolve));
console.log("probe synced");

const deadline = Date.now() + 30_000;
function until(cond, what) {
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      const value = cond();
      if (value) {
        clearInterval(timer);
        resolve(value);
      } else if (Date.now() > deadline) {
        clearInterval(timer);
        reject(new Error(`timeout waiting for ${what}`));
      }
    }, 100);
  });
}

// 1. A native peer publishes user + cursor (anchor/head relative positions).
const nativeState = await until(() => {
  const states = [...provider.awareness.getStates().entries()].filter(
    ([id]) => id !== provider.awareness.clientID,
  );
  const native = states.find(
    ([, s]) => s.user?.name && s.cursor?.anchor && s.cursor?.head,
  );
  return native ? native[1] : null;
}, "a native peer's awareness cursor");
console.log("native cursor seen:", JSON.stringify(nativeState));

// The native anchor must resolve into this replica's document.
const anchor = Y.createAbsolutePositionFromRelativePosition(
  Y.createRelativePositionFromJSON(nativeState.cursor.anchor),
  document,
);
if (!anchor) throw new Error("native cursor anchor did not resolve");
console.log(
  `native anchor resolves: index ${anchor.index} in ${anchor.type.constructor.name}`,
);

// 2. Publish a web cursor into the first paragraph's text, as
//    CollaborationCursor does (relative positions, assoc -1).
const fragment = document.getXmlFragment("prosemirror");
const firstText = await until(() => {
  for (const paragraph of fragment.toArray()) {
    if (!(paragraph instanceof Y.XmlElement)) continue;
    const child = paragraph.get(0);
    if (child instanceof Y.XmlText && child.length > 0) return child;
  }
  return null;
}, "a non-empty text node to anchor into");

const at = Math.min(2, firstText.length);
const position = Y.relativePositionToJSON(
  Y.createRelativePositionFromTypeIndex(firstText, at, -1),
);
provider.setAwarenessField("user", { name: "Probe (Web)", color: "#2563eb" });
provider.setAwarenessField("cursor", { anchor: position, head: position });
console.log("web cursor published at text index", at);

console.log("CURSOR PROBE OK");
if (!stay) {
  provider.destroy();
  process.exit(0);
}
console.log("staying alive for screenshots…");
