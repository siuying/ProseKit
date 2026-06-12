import ProseModel

struct StrikeStyle: MarkStyle {
    let markType = "strike"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.strikethrough = true
    }
}
