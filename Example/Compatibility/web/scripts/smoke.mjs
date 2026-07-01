// Smoke test: two headless hocuspocus peers converge on the shared fragment,
// and awareness states propagate.
import { HocuspocusProvider } from "@hocuspocus/provider";
import * as Y from "yjs";
import WebSocket from "ws";

const url = `ws://localhost:${process.env.PORT ?? 4321}/collaboration`;
const name = "prosekit-compatibility-smoke";

function makePeer(label) {
  const document = new Y.Doc();
  const provider = new HocuspocusProvider({
    url,
    name,
    document,
    WebSocketPolyfill: WebSocket,
  });
  return { label, document, provider };
}

const a = makePeer("A");
const b = makePeer("B");

await Promise.all(
  [a, b].map(
    (p) =>
      new Promise((resolve) => p.provider.on("synced", resolve)),
  ),
);
console.log("both peers synced");

// Peer A writes a paragraph into the y-prosemirror fragment.
const fragA = a.document.getXmlFragment("prosemirror");
a.document.transact(() => {
  const para = new Y.XmlElement("paragraph");
  const text = new Y.XmlText();
  text.insert(0, "hello from peer A");
  para.insert(0, [text]);
  fragA.insert(0, [para]);
});

// Peer A publishes awareness presence.
a.provider.setAwarenessField("user", { name: "Smoke A", color: "#ff0000" });

// Wait for peer B to observe both.
const deadline = Date.now() + 5000;
function until(cond, what) {
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (cond()) {
        clearInterval(timer);
        resolve();
      } else if (Date.now() > deadline) {
        clearInterval(timer);
        reject(new Error(`timeout waiting for ${what}`));
      }
    }, 50);
  });
}

await until(
  () => b.document.getXmlFragment("prosemirror").toString().includes("hello from peer A"),
  "document convergence",
);
console.log("document converged:", b.document.getXmlFragment("prosemirror").toString());

await until(() => {
  const states = [...b.provider.awareness.getStates().values()];
  return states.some((s) => s.user?.name === "Smoke A");
}, "awareness propagation");
console.log("awareness propagated");

a.provider.destroy();
b.provider.destroy();
console.log("SMOKE OK");
process.exit(0);
