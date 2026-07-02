# Compatibility demo — ProseKit ⇄ Tiptap over Hocuspocus

Live, multi-party proof of the wire-format contract the interop fixtures pin
down (`Tests/Interop`): a browser Tiptap editor, an iOS ProseKit editor, and a
macOS ProseKit editor all editing one document through a Hocuspocus server,
with awareness (who's here, colored cursors) on top.

```
Example/Compatibility/
├── web/          # Hocuspocus server + Tiptap frontend, one port, one command
├── Shared/       # SwiftUI app sources shared by the iOS and macOS targets
├── project.yml   # xcodegen spec: CompatibilityExample (iOS) + CompatibilityExampleMac
└── README.md
```

Everyone meets in room `prosekit-compatibility` on the Yjs fragment
`prosemirror` (`YBinding.defaultFragmentName`, matching Tiptap's
`Collaboration.configure({ field: 'prosemirror' })`).

## Run the web side (server + browser editor)

```sh
cd Example/Compatibility/web
npm install
npm run serve:all
```

One process serves everything on port 4321:

- `http://localhost:4321` — Tiptap editor (toolbar, live cursors, participants)
- `ws://localhost:4321/collaboration` — Hocuspocus

Vite runs in middleware mode inside an Express server and Hocuspocus answers
the WebSocket upgrades on `/collaboration`, so HTTP and WS share the port.
Open two browser tabs to see web↔web editing and named cursors immediately.

`npm run smoke` runs a headless two-peer convergence + awareness check against
a running server.

## Run the native apps

Prerequisites: a sibling `SwiftYrs` checkout (the package already expects
`../SwiftYrs`, and this project also uses its `SwiftYrsHocuspocus` provider)
and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
cd Example/Compatibility
xcodegen generate
open CompatibilityExample.xcodeproj
```

Run the `CompatibilityExample` (iOS Simulator) or `CompatibilityExampleMac`
scheme while `npm run serve:all` is up. Each app connects to
`ws://localhost:4321/collaboration`, joins the shared document, and shows a
connection badge plus a participants bar with every peer's random name/color.

Note: the SwiftYrs FFI xcframework ships arm64 simulator slices only — build
for a concrete arm64 simulator, not the generic destination.

### Test hook

`-autotype "some text"` types into the editor ~5s after launch, so scripts can
verify the native→web direction without driving the keyboard, e.g.:

```sh
xcrun simctl launch <device> com.siuying.CompatibilityExample -autotype "hi from iOS"
open CompatibilityExampleMac.app --args -autotype "hi from the Mac"
```

## Architecture notes

**Two replicas per native app, bridged.** A YDoc handle needs a single
serialization owner. `YBinding` owns its replica on the MainActor;
`HocuspocusProvider` is its own actor and applies remote updates on its own
executor — sharing one YDoc crashes (`MainActor.assumeIsolated` in the
binding's observers) and would race the CRDT handle. So `EditorSession` binds
the editor to a MainActor-owned YDoc, hands the provider a separate
network-side YDoc, and forwards update bytes between them on each side's
owning executor (see `Shared/EditorSession.swift`). Echoes terminate because
applying an already-known Yjs update is a no-op and emits no update event.
Awareness is bridged the same way. If `SwiftYrsHocuspocus` grows a way to
apply updates on a caller-chosen executor, the bridge collapses to one doc.

**Presence keep-alive.** Peers prune awareness states not renewed within ~30s
(y-protocols `outdatedTimeout`). The JS provider re-broadcasts on a timer; the
Swift provider doesn't, so the session republishes its state every 10s.

## Awareness status

- Random name + color per participant: all peers, shown in every UI. ✅
- Remote cursors: all directions. ✅ Web peers use Tiptap
  `CollaborationCursor`; the native session publishes the same
  `cursor: {anchor, head}` awareness shape (y-prosemirror relative positions,
  via `YBinding.relativePosition(for:)`) and paints remote peers through the
  Selection Layer's remote chrome (`ProseView.remoteSelections`, the plan's
  Phase 1b). `scripts/cursor-probe.mjs` verifies both directions headlessly:
  it waits for a native cursor, resolves it, and publishes a web cursor for
  the native apps to draw (`--stay` keeps it alive for screenshots).
