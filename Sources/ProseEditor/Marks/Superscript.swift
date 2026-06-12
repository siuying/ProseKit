import ProseModel

struct SuperscriptStyle: MarkStyle {
    let markType = "superscript"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.superscript = 1
    }
}

struct SubscriptStyle: MarkStyle {
    let markType = "subscript"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.superscript = -1
    }
}
