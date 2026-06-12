import CoreText
import ProseModel

struct ItalicStyle: MarkStyle {
    let markType = "italic"

    func apply(_ mark: Mark, to style: inout RunStyle) {
        style.traits.insert(.traitItalic)
    }
}
