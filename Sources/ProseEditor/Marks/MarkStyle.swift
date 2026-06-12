import CoreText
import ProseModel

/// The CoreText styling a run accumulates as its Marks are applied. Marks
/// contribute independently: bold/italic add font traits, code switches to a
/// monospace family. Block-level concerns (a heading's bold, the point size)
/// are layered in by `BlockStyle`, not here.
struct RunStyle {
    var monospace = false
    var traits: CTFontSymbolicTraits = []
    /// CTLine draws this (kCTUnderlineStyleAttributeName).
    var underline = false
    /// CoreText has no strikethrough attribute; the Canvas draws it manually.
    var strikethrough = false
    /// The highlight Mark's raw `color` Attr value, preserved verbatim. The
    /// Canvas parses it at draw time and fills the run's background; an
    /// unparseable value draws nothing (ADR 0005).
    var highlight: String?
    /// CoreText vertical text position: 1 superscript, -1 subscript, 0 baseline.
    var superscript = 0
    /// A link run renders in the link tint and underlined.
    var link = false
}

/// One inline Mark's contribution to a run's `RunStyle`. The Mark itself is
/// passed so a unit can read its Attrs (e.g. highlight's `color`). Each
/// supported Mark is a single unit; adding one means adding a `MarkStyle` and
/// listing it in `MarkStyles.all` — `BlockStyle` itself never learns about
/// specific Mark types. An unrecognised Mark has no unit and so contributes
/// nothing, rendering as plain text (ADR 0006).
protocol MarkStyle: Sendable {
    var markType: String { get }
    func apply(_ mark: Mark, to style: inout RunStyle)
}

enum MarkStyles {
    static let all: [any MarkStyle] = [
        BoldStyle(), ItalicStyle(), CodeStyle(), StrikeStyle(), UnderlineStyle(), HighlightStyle(),
        SuperscriptStyle(), SubscriptStyle(), LinkStyle(),
    ]

    static func style(for type: String) -> (any MarkStyle)? {
        all.first { $0.markType == type }
    }
}
