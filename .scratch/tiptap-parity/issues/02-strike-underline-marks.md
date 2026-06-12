# 02 — Strike + underline marks

Status: done

## What to build

Two inline Marks, `strike` and `underline`, added through the per-feature unit
seam from slice 01. This is where the `RunStyle` seam grows past font traits:
neither Mark is a font trait.

- **underline** → `kCTUnderlineStyleAttributeName`; `CTLine` draws it.
- **strike** → CoreText has no strikethrough attribute that `CTLineDraw`
  honours, so the run is flagged with a custom attribute and the Canvas strokes
  a line through the x-height after drawing the glyphs, using the run geometry
  from the same `CTLine` so it stays aligned.

`toggleMark(_:)` already drives both (generic over any `Mark`); the ⌘⇧S
shortcut is slice 16.

## Acceptance criteria

- [x] `strike` and `underline` are in `Schema.slice1.marks`; both round-trip
- [x] `underline` sets the CoreText underline attribute on the run
- [x] `strike` flags the run with `BlockStyle.strikethroughAttributeName`
- [x] A struck run and an underlined run each render differently from plain text
- [x] Each is a single `MarkStyle` unit (`Marks/Strike`, `Marks/Underline`);
      `BlockStyle` gained `RunStyle.underline`/`.strikethrough` but learned no
      specific Mark type

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: `RunStyle` extended from `{monospace, traits}` to also carry
`underline`/`strikethrough` decorations — the first real second members that
justify the seam. Strikethrough drawing is manual (`ProseView.drawStrikethrough`)
at x-height/2, thickness scaled from font size; exact vertical placement is a
visual-polish item worth confirming in the app. Slice-01 unknown-mark tests were
repointed from `strike`/`highlight` (now real) to fictional types (`xyzzy`,
`frobnicate`) so they keep exercising the unknown-mark path.
