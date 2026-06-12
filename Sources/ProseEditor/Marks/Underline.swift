import ProseModel

struct UnderlineStyle: MarkStyle {
    let markType = "underline"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.underline = true
    }
}
