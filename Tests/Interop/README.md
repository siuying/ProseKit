# ProseKitYjs interop fixture

A headless [`y-prosemirror`](https://github.com/yjs/y-prosemirror) peer — the same
binding Tiptap drives in the browser — used to prove `ProseKitYjs` converges with a
real JS peer, not just a second `SwiftYrs` document.

`interop.mjs` encodes/decodes the slice-1 paragraph (`doc > paragraph > text`) on
the `"prosemirror"` fragment and exchanges standard **Yjs v1 update bytes** with the
Swift `YBinding`. Identical text on both sides is genuine ProseKit ⇄ browser-peer
convergence.

## Setup

```sh
cd Tests/Interop
npm install
```

`YBindingInteropTests` then runs it automatically (it `XCTSkip`s when Node or the
`node_modules` are absent, e.g. in a network-restricted CI). Point it at a specific
Node with the `NODE_BINARY` environment variable.

## Modes

```sh
node interop.mjs encode "<text>" <outFile>   # build a y-prosemirror update  (JS -> Swift)
node interop.mjs decode <inFile>             # print text from a Swift update (Swift -> JS)
```

## Scope

This proves the **wire-format** convergence (the gap the tracer-bullet issue
centred on). A live Hocuspocus/websocket + headless-browser harness is the
networked superset; it builds on this same fixture and the `SwiftYrsHocuspocus`
provider, and is tracked by the later collaboration slices.
