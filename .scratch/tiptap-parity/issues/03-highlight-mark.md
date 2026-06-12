# 03 — Highlight mark (multicolor, parse-or-plain, dark mode)

Status: done

## What to build

The `highlight` Mark with a `color` Attr (Q7). Stored plain like Tiptap; the
value is preserved verbatim (ADR 0005). Rendering:

- A parseable hex (`#rrggbb` / `#rgb`) fills the run's background.
- An unparseable value (CSS variable, named colour) keeps the Mark but draws no
  background.
- Multicolor: different colours render differently.
- Dark mode: the shipped default-palette colours map to dynamic colours at draw
  time; arbitrary colours render literally in both modes.

The `MarkStyle` seam grew to receive the `Mark` (so a unit can read its Attrs).
Background fill, like strikethrough, is a manual Canvas pass — CoreText has no
honoured background attribute. The palette popover and customization API are
slice 09.

## Acceptance criteria

- [x] `highlight` is in `Schema.slice1.marks`; the `color` Attr round-trips verbatim
- [x] `HighlightColor.parseHex` parses `#rrggbb`/`#rgb`; returns nil for CSS
      variables / named / empty values
- [x] A shipped palette colour resolves to different light vs dark colours; an
      arbitrary colour is stable across modes
- [x] A parseable highlight fills a background; an unparseable one draws nothing
- [x] Two different colours render differently (multicolor)
- [x] One `MarkStyle` unit (`Marks/Highlight`) + `Marks/HighlightColor`; the
      `MarkStyle` protocol now passes the `Mark` (Attrs), used by no other unit

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: Colour parse + palette resolution happen at draw time, not layout,
so dynamic (dark-mode) colours resolve against the Canvas's trait collection.
`MarkStyle.apply` gained the `Mark` parameter (the five earlier units ignore it).
Default palette is 5 colours; the customizable palette API is slice 09.
