# Prose Example

Open `ProseExample.xcodeproj`, select an iOS simulator, and run the
`ProseExample` scheme. The app is a catalog of demos, each hosting a `ProseView`
on a different document:

- **Simple Editor** — the Tiptap-parity formatting set: a scrollable formatting
  bar attached as the keyboard's `inputAccessoryView`, with a heading dropdown,
  every inline mark (bold, italic, underline, strike, code, super/subscript),
  highlight swatches, links, and text alignment. The block dropdown and mark
  buttons reflect the editor's active state.
- **Rich Text Basics** — headings, paragraphs, and inline marks.
- **Marks & Formatting** — toggle marks/headings from a toolbar or ⌘B/⌘I.
- **Selection & Autoscroll** — system selection handles, edit menu, autoscroll.
- **Structural Editing** — Return splits a block, Backspace joins it back.
- **Large Document** — 2,000 paragraphs for scrolling/typing performance.

## Launch arguments

- `-simple` — deep-link straight to the Simple Editor (handy for screenshots).
- `-paragraphs N` — skip the catalog and open a bare editor on an N-paragraph
  synthetic document (used by the performance UI tests).
