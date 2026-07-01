# ProseKit

A native iOS rich-text editor built on a custom CoreText layout engine over a
[ProseMirror](https://prosemirror.net)-style document model. The document tree is
the structural authority; the rendered layout is a projection of it, never the
other way around.

![Demo](./assets/demo.gif)

ProseKit is written in pure Swift with no web view. It typesets directly with
CoreText, models every edit as an invertible, serializable step on an immutable
document, and speaks the same [Tiptap](https://tiptap.dev) / ProseMirror JSON
that the web editors do — so documents round-trip between platforms.

## Highlights

- **ProseMirror-style model** — the document is an immutable, persistent tree.
  Editing produces a new document; every change is an invertible `Step` inside a
  `Transaction`.
- **Custom CoreText layout** — no `UITextView`, no web view. Block nodes are laid
  out as a tree of layout boxes and painted only where they intersect the
  viewport.
- **Tiptap-compatible JSON** — `Document` is `Codable` and reads/writes the same
  JSON shape as Tiptap's Simple Editor, so content interoperates with the web.
- **Rich formatting set** — headings, paragraphs, blockquotes, bullet/ordered/
  task lists with real nesting, and inline marks: bold, italic, underline,
  strike, code, super/subscript, highlight, and links.
- **Input rules & commands** — Markdown-style shortcuts (`# ` for a heading) and
  composable `(state, dispatch?) -> Bool` commands for every editing intent.

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.0+ (Xcode 16+)

## Installation

ProseKit is distributed as a Swift Package with two products:

- `ProseModel` — the pure document model (no UIKit dependency).
- `ProseEditor` — the interactive editor view (`ProseView`), depends on
  `ProseModel`.

### Swift Package Manager (Xcode)

In Xcode, choose **File ▸ Add Package Dependencies…**, enter the repository URL,
and add the `ProseEditor` product (and `ProseModel` if you want the model on its
own) to your target.

### Swift Package Manager (`Package.swift`)

```swift
dependencies: [
    .package(url: "https://github.com/siuying/ProseKit.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ProseEditor", package: "ProseKit"),
        ]
    ),
]
```

## Usage

### Build a document and show it

`ProseView` is a `UIScrollView` subclass that conforms to `UITextInput`, so it
drops into any UIKit hierarchy and gets the system keyboard, selection handles,
and edit menu for free.

```swift
import UIKit
import ProseModel
import ProseEditor

let document = Document(.doc([
    .heading(level: 1, [.text("Rich Text Basics")]),
    .paragraph([
        .text("Text carries marks: "),
        .text("bold", marks: [.bold]),
        .text(", "),
        .text("italic", marks: [.italic]),
        .text(", and "),
        .text("code", marks: [.code]),
        .text(". Marks compose, so "),
        .text("bold italic", marks: [.bold, .italic]),
        .text(" works too."),
    ]),
]))

let editor = ProseView(document: document)
editor.frame = view.bounds
editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
view.addSubview(editor)
```

### Apply formatting

Formatting commands are exposed directly on the view; query the active state to
drive a toolbar's selected/enabled styling.

```swift
editor.toggleMark(.bold)
editor.toggleMark(.italic)
editor.toggleHeading(level: 2)
editor.wrapInList("bulletList")
editor.setLink("https://example.com")

let boldOn = editor.isActive(.bold)        // reflect toolbar state
let block  = editor.activeBlockType        // "paragraph", "heading", …

editor.onStateChange = { /* refresh the toolbar */ }
```

### Markdown shortcuts (input rules)

ProseKit ships Tiptap-style **input rules**: patterns watched at the caret that
rewrite just-typed text into structure or formatting. They fire while typing in
both shells and are on by default. Backspace immediately after a shortcut
restores the literal Markdown you typed.

| Type this | Get |
| --- | --- |
| `# ` … `###### ` | Heading levels 1–6 |
| `> ` | Blockquote |
| `- ` or `* ` | Bullet list |
| `1. ` | Ordered list |
| `*text*` or `_text_` | _Italic_ |
| `**text**` or `__text__` | **Bold** |
| `` `text` `` | `Code` |
| `~~text~~` | ~~Strike~~ |

Block shortcuts fire at the start of a block; inline shortcuts fire on the
final delimiter pair before the caret. Typing after an inline shortcut is plain
(the mark is not carried). Composition/IME and paste never run the shortcuts —
pasted Markdown is inserted verbatim.

```swift
editor.inputRulesEnabled = false   // opt out of all markdown shortcuts
```

### Interoperate with Tiptap / ProseMirror JSON

`Document` is `Codable` and round-trips the same JSON that Tiptap and
ProseMirror use, so you can load content from a server or hand it back to a web
client unchanged.

```swift
let json = Data(/* Tiptap / ProseMirror document JSON */)
let document = try JSONDecoder().decode(Document.self, from: json)
let editor = ProseView(document: document)

// …and back out
let exported = try JSONEncoder().encode(editor.document)
```

### Persist or collaborate with Yjs

The `ProseKitYjs` product persists content as a Yjs (SwiftYrs) update blob and
converges an editor with a `YDoc` — for local single-writer storage or mergeable
multi-device collaboration. See
[`docs/embedding-yjs-persistence.md`](./docs/embedding-yjs-persistence.md) for the
blob round-trip, the per-platform `ProseView` surface, and when to bind a live
`YBinding` vs. re-encode on save.

### Use the model on its own

`ProseModel` has no UIKit dependency, so it builds and runs anywhere — useful for
server-side processing, diffing, or document transforms.

```swift
import ProseModel

let document = Document(.doc([.paragraph([.text("Hello")])]))
let plain = document.plainText
```

## Project structure

```
.
├── Package.swift            # SwiftPM manifest: ProseModel + ProseEditor products
├── Sources/
│   ├── ProseModel/          # Pure document model — no UIKit
│   │   ├── Document.swift    #   immutable document tree + positions
│   │   ├── Node.swift        #   block & inline nodes, factory helpers
│   │   ├── Mark.swift        #   inline formatting marks
│   │   ├── Step.swift        #   invertible, serializable edits
│   │   ├── Transaction.swift #   atomic batches of steps
│   │   ├── Mapping.swift     #   remap positions across steps
│   │   ├── Selection.swift   #   text selection in positions
│   │   └── Schema/           #   node/mark rules the document must satisfy
│   └── ProseEditor/         # Interactive editor — CoreText + UIKit
│       ├── ProseView.swift   #   the editor view (UIScrollView + UITextInput)
│       ├── EditorState.swift #   active marks/blocks, command availability
│       ├── Commands.swift    #   editing intents as composable commands
│       ├── InputRule.swift   #   typing-time rewrites (Markdown shortcuts)
│       ├── Layout.swift      #   CoreText layout box tree
│       ├── CanvasView.swift  #   viewport-clipped painting
│       └── Marks/            #   per-mark CoreText styling
├── Tests/
│   ├── ProseModelTests/
│   └── ProseEditorTests/
├── Example/                 # ProseExample — a SwiftUI catalog app of demos
├── CONTEXT.md               # domain language / architecture reference
└── docs/                    # ADRs and research notes
```

## Architecture

The document tree is the single source of truth. Layout is a projection of it:

1. **Model** — an immutable `Document` of block and inline `Node`s. Edits are
   `Step`s gathered into a `Transaction`, never in-place mutation.
2. **Layout** — each block node maps to a *layout box*; the boxes stack into a
   tree that mirrors the document's structure and typeset their text via
   CoreText into line fragments.
3. **Paint** — only the layout boxes intersecting the visible viewport are drawn
   onto the canvas. Scrolling moves the viewport; it never re-lays-out or mutates
   the document.

See [`CONTEXT.md`](./CONTEXT.md) for the full domain glossary and the
[`docs/adr/`](./docs/adr) directory for the architecture decisions behind it.

## Example app

The [`Example/`](./Example) directory contains **ProseExample**, a SwiftUI
catalog of demos (Simple Editor, Tiptap parity, UITextView comparison, lists,
large documents, and more). Open `Example/ProseExample.xcodeproj`, pick an iOS simulator, and run the
`ProseExample` scheme. See [`Example/README.md`](./Example/README.md) for details.

## Testing

ProseKit has two test loops. The fast one runs on the host with `swift test`;
the UIKit editor tests need an iOS simulator via `xcodebuild`.

```sh
# Fast, cross-platform loop: model + Yjs-binding + platform-independent
# editor tests. Runs on macOS with no simulator.
swift test

# UIKit-dependent editor tests (ProseView / UITextInput) need a simulator.
# Pin the OS explicitly: more than one "iPhone 17 Pro" can be installed with
# different iOS versions, and the tests are only validated on the canonical
# one below.
xcodebuild test -scheme ProseKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1'

# Or use the helper, which resolves the pinned device to a concrete udid so it
# never targets a same-named simulator on a different iOS version:
scripts/test-ios.sh
```

> **Canonical simulator:** iPhone 17 Pro on **iOS 26.1**. Always pass `OS=` (or
> a specific `id=`) so the run is reproducible — targeting `name=iPhone 17 Pro`
> alone can silently pick a different installed OS.

## License

ProseKit is available under the [MIT License](./LICENSE).
