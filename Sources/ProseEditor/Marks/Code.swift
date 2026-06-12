import CoreText
import ProseModel

struct CodeStyle: MarkStyle {
    let markType = "code"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.monospace = true
    }
}
