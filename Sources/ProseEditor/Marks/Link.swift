import ProseModel

/// A link renders in the link tint and underlined (Q9.6). An explicit underline
/// Mark on the same run is therefore invisible — it sets the same decoration.
/// The `href`/`target`/`rel`/`class` Attrs are preserved by the model (ADR 0005)
/// and consumed by the link popover (slice 08), not by rendering.
struct LinkStyle: MarkStyle {
    let markType = "link"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.link = true
        style.underline = true
    }
}
