# Embedding a Yjs-persisted editor

How to embed a ProseKit editor whose content is persisted as a Yjs (SwiftYrs)
update blob — either for **local single-writer storage** or for **mergeable,
multi-device collaboration**. This is the integration path behind the `ProseKitYjs`
product; the README's Tiptap-JSON round-trip is a *different* persistence strategy
(a plain `Codable` snapshot, no CRDT merge).

## Products

| Product | Use it for |
|---|---|
| `ProseModel` | The pure `Document` tree (`Codable`, `document.plainText`). No UIKit/AppKit. |
| `ProseEditor` | The interactive editor view + `EditorCore`. UIKit on iOS, AppKit on macOS. |
| `ProseKitYjs` | `YBinding` — converges an `EditorCore` with a Yjs `YDoc`/`YXmlFragment`. Depends on `SwiftYrs`. |

## Platform surface (read this first)

`ProseView` is **two different types** sharing one name, and their visibility
differs — do not assume one from the other:

| | iOS (`UIKit`) | macOS (`AppKit`) |
|---|---|---|
| Base class | `UIScrollView, UITextInput` | `NSScrollView` |
| `init(document:schema:)` | public | public |
| `var document` (get/set) | public | public |
| `var core: EditorCore` | **internal** (module-private) | **`public`** |
| Observe edits | `public var onStateChange` | `core.didApplyTransaction` (`EditorCore` is public) |
| SwiftUI wrapper | **none built-in** — wrap in your own `UIViewRepresentable` | `MacProseEditorView: NSViewRepresentable` (takes a `Document`; no Yjs) |

Consequences:
- On **macOS** you can attach a `YBinding` to the *rendered* editor, because
  `proseView.core` is public.
- On **iOS** `core` is not public, so to bind the live view you must either add a
  public accessor here, or drive persistence from `proseView.document` instead of
  a bound `EditorCore`.
- Neither built-in SwiftUI wrapper wires up Yjs — you own the `YDoc`/`YBinding`
  lifecycle.

## The blob round-trip (SwiftYrs)

```swift
import ProseKitYjs   // ProseKitYjs.makeDocument()
import SwiftYrs       // YDoc, YUpdate

// Create / load
let doc = ProseKitYjs.makeDocument()        // a fresh YDoc
try doc.apply(.v1(blob))                     // seed from a stored Data blob (skip if new)

// Persist
let blob: Data = try doc.encodeStateAsUpdateV1().data

// Plain text (e.g. for a list preview or full-text index)
let plain: String = proseView.document.plainText
```

`YBinding.join()` is internal; trigger the initial seed/reconcile via the public
`attach(syncedSignal:)`, feeding a stream that yields `true` once. Both peers (or
your seed code) MUST agree on the fragment name — `YBinding.defaultFragmentName`
is `"prosemirror"` (y-prosemirror's default; Tiptap uses `"default"`).

## Mode A — local single-writer persistence

If you do not need cross-device merge, the simplest approach is to **read
`proseView.document` on save and re-encode**:

```swift
// Save (debounced): encode the current Document into a throwaway YDoc.
@MainActor func encodeBlob(from document: Document) throws -> (blob: Data, plain: String) {
    let core = EditorCore(document: document)
    let doc = ProseKitYjs.makeDocument()
    let binding = YBinding(core: core, doc: doc)
    let (stream, cont) = AsyncStream.makeStream(of: Bool.self)
    binding.attach(syncedSignal: stream)
    cont.yield(true); cont.finish()          // first `true` runs join → encodes the Document
    defer { binding.detach() }
    return (try doc.encodeStateAsUpdateV1().data, document.plainText)
}
```

Trade-off: re-encoding from the `Document` each save mints a **fresh YDoc** (new
client state every time). That is fine for single-writer local storage but will
**not merge cleanly** if two devices edit the same note — each save is a
from-scratch CRDT.

## Mode B — mergeable collaboration / multi-device

Keep **one persistent `YDoc`** loaded from the blob and bind it to the live
editor's `EditorCore` for the whole session, so edits accumulate as CRDT
operations and concurrent edits merge:

```swift
// macOS (core is public)
let doc = ProseKitYjs.makeDocument()
if let blob { try doc.apply(.v1(blob)) }

let proseView = ProseView(document: Document(.doc([.paragraph([])])))
let binding = YBinding(core: proseView.core, doc: doc)

let (stream, cont) = AsyncStream.makeStream(of: Bool.self)
binding.attach(syncedSignal: stream)
cont.yield(true)                  // seed: non-empty replica → editor; empty → seed from editor
// keep `cont` to yield `true` again after each provider reconnect-sync

// Persist whenever you like (debounced); the blob preserves CRDT identity:
let blob = try doc.encodeStateAsUpdateV1().data
```

`YBinding` also provides collaborative undo (see ADR
[0010](./adr/0010-collaborative-undo-delegates-to-yundomanager.md)) and is the
convergence authority (ADR
[0011](./adr/0011-ydoc-is-the-convergence-authority.md)). For cross-platform
interop with y-prosemirror peers, see ADR
[0012](./adr/0012-collaboration-targets-cross-platform-y-prosemirror.md).

## Picking a mode

- **One device, just want rich text saved** → Mode A.
- **Sync / multiple writers, or you want history to merge** → Mode B.
