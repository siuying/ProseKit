import ProseModel

struct HighlightStyle: MarkStyle {
    let markType = "highlight"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        // Store the raw value verbatim (ADR 0005). Parseability and dark-mode
        // mapping are decided at draw time; an absent or unparseable value
        // simply draws no background.
        style.highlight = mark.attrs["color"]?.stringValue
    }
}
