# 05 — Link mark + paste-URL-onto-selection

Status: done

## What to build

The `link` Mark (Q6) and one of its entry points. Schema attr `href`, with
`target`/`rel`/`class` preserved verbatim (ADR 0005). Render: link tint +
underline (Q9.6) — an explicit underline Mark on a link is therefore invisible.

- `Commands.setLink(href:)` wraps the (non-empty) selection in a link Mark —
  shared by the link popover (slice 08) and by paste.
- Pasting a sole URL onto a selection links the selection instead of replacing
  it (`LinkDetection.soleURL` via NSDataDetector). Autolink-while-typing and
  caret-in-link popover behaviour are slice 08.

## Acceptance criteria

- [x] `link` in `Schema.slice1.marks`; `href` + extra attrs round-trip verbatim
- [x] `Commands.setLink(href:)` wraps a selection; no-op on a collapsed caret
- [x] `LinkDetection.soleURL` accepts a lone URL (trims surrounding space),
      rejects URLs embedded in text and non-URLs
- [x] A link renders differently from plain (tint + underline)
- [x] A link + explicit underline Mark renders identically to the link alone
- [x] Pasting a URL onto a selection links it (keeps the text), not replaces it
- [x] One `MarkStyle` unit (`Marks/Link`); `RunStyle.link` added

## Blocked by

- 01 — Per-feature format units.

## Comments

2026-06-12: Link tint is a baked sRGB system-blue CGColor (legible both modes)
rather than foreground-from-context, since the attributed string is built at
layout time off the view's traits; a fully trait-reactive link colour would need
per-run draw and can come with the popover slice. Tap-to-navigate vs caret is a
ProseView gesture concern deferred to slice 08.
