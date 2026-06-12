# 01 — Per-feature format units + unknown-mark preservation (pathfinder)

Status: done

## What to build

The pathfinder slice for Tiptap Simple Editor parity. Two things:

1. **Unknown-mark preservation** (ADR 0006 phase 1). A Tiptap document may carry
   Mark types outside our supported set (`strike`, `highlight`, …). The Schema
   must keep them in the model rather than reject the document, and rendering
   must treat an unrecognised Mark as plain text. Re-export stays byte-faithful
   (attrs included, per ADR 0005). Unknown *node* types are out of scope here —
   they still raise a hard load error until Opaque Nodes land (slice 18); never
   silent acceptance or stripping.

2. **Per-feature format units** (Q2c — internal only, no public Extension API
   yet, ps1/06 untouched). Replace the hardcoded switches with one unit per
   format so later slices add a format by adding a file, not by editing a switch:
   - `ProseModel`: each Block Node's structural rule is a `NodeRule`
     (`Schema/DocRule`, `ParagraphRule`, `HeadingRule`); `Schema.validate`
     dispatches through `NodeRules.rule(for:)` instead of a `switch`.
   - `ProseEditor`: each Mark's CoreText contribution is a `MarkStyle`
     (`Marks/Bold`, `Italic`, `Code`) accumulated into a `RunStyle`;
     `BlockStyle.font` iterates units instead of testing `.bold`/`.italic`/`.code`.
   - `Commands` needs no restructure: `toggleMark(_:)` is already generic over
     any `Mark`, so a new Mark needs no new Command.

   The schema rule and the style/render contribution live in different modules
   by design (ProseModel is the structural authority; rendering is a projection,
   per CONTEXT.md), so a feature is one unit per module rather than one physical
   file.

## Acceptance criteria

- [x] A text node carrying an unsupported Mark (`strike`) passes `Schema.validate`
- [x] Unknown Marks survive a JSON round-trip verbatim, attrs included (ADR 0005/0006)
- [x] An unknown *node* type still throws a `SchemaError` (no silent accept/strip)
- [x] An unsupported Mark contributes no CoreText styling — the run renders
      identically to plain text; a known Mark (`bold`) still renders differently
- [x] `Schema.validate`'s per-type switch is replaced by per-`NodeRule` units;
      public Schema API (`nodes`/`marks`/`validate`) unchanged
- [x] `BlockStyle.font` resolves Marks through per-`MarkStyle` units; bold/italic/
      code render exactly as before (existing rendering/layout tests still green)

## Blocked by

- None (first slice).

## Comments

2026-06-12: Implemented via `/tdd`. Behaviour driven first (4 RED→GREEN cycles:
schema preserves unknown mark; verbatim JSON round-trip; unknown-node boundary
still throws; unknown mark renders as plain text), then the switches refactored
into units under green. Note: `Schema.marks` is now unused by validation (ADR
0006 dropped the gate); kept as the enumerated render-supported set for the
toolbar active-state slice (06). The unknown-node test pins behaviour, not the
message — today an `image` under `doc` trips the parent content rule ("doc may
only contain block nodes") before the top-level "unknown node type" check; a
clearer load error is slice 18's concern. Tests: `SchemaTests`,
`DocumentJSONTests`, `BlockStyleTests` (new) + full editor suite green.
