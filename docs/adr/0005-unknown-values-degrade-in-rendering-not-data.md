# Unknown attr values degrade in rendering, never in data

Tiptap documents carry attr values we may not understand (e.g. a `highlight`
color stored as a CSS variable, or attrs our UI never sets like `link.rel`).
We render what we can parse and render nothing special for what we can't —
but the stored value is always preserved verbatim, so re-exporting a document
never loses or rewrites data we merely failed to display. Normalizing values
on import was rejected: it would silently corrupt round-trips with Tiptap
(ADR 0003) for the sake of tidier data we don't own.
