// Single-port dev server: Vite serves the tiptap frontend over HTTP while
// Hocuspocus answers WebSocket upgrades on /collaboration — one process, one
// port, so native peers and the browser hit the same ws://localhost:1234.
import { createServer } from "node:http";
import express from "express";
import { WebSocketServer } from "ws";
import { Hocuspocus } from "@hocuspocus/server";
import { createServer as createViteServer } from "vite";

// 1234 is the customary hocuspocus port but collides with LM Studio's local
// API server; 4321 keeps localhost demos out of each other's way.
const PORT = Number(process.env.PORT ?? 4321);

const hocuspocus = new Hocuspocus({
  name: "prosekit-compatibility",
  async onConnect({ request }) {
    console.log(`[hocuspocus] peer connected (${request.headers["user-agent"] ?? "unknown agent"})`);
  },
  async onDisconnect() {
    console.log("[hocuspocus] peer disconnected");
  },
});

const app = express();
const server = createServer(app);

const vite = await createViteServer({
  root: import.meta.dirname,
  appType: "spa",
  server: {
    middlewareMode: true,
    // Vite's HMR socket shares this HTTP server; it claims upgrades that
    // carry the `vite-hmr` websocket subprotocol, we take the rest.
    hmr: { server },
  },
});
app.use(vite.middlewares);

const wss = new WebSocketServer({ noServer: true });
server.on("upgrade", (request, socket, head) => {
  if (request.headers["sec-websocket-protocol"] === "vite-hmr") return;
  if (request.url?.startsWith("/collaboration")) {
    wss.handleUpgrade(request, socket, head, (ws) => {
      hocuspocus.handleConnection(ws, request);
    });
  } else {
    socket.destroy();
  }
});

server.listen(PORT, () => {
  console.log(`ProseKit compatibility demo:`);
  console.log(`  frontend  http://localhost:${PORT}`);
  console.log(`  hocuspocus ws://localhost:${PORT}/collaboration`);
});
