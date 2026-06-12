import CoreText
import ProseModel

struct BoldStyle: MarkStyle {
    let markType = "bold"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.traits.insert(.traitBold)
    }
}
