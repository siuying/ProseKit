import CoreGraphics
import CoreText
import Foundation
import ProseModel

/// Resolves marks and block types to concrete CoreText attributes. Layout and
/// drawing must both go through this so measured text is exactly drawn text.
enum BlockStyle {
    static let bodyFontSize: CGFloat = 17

    /// Heading point size by `level` (Q9.1): a heading is no longer a single
    /// size. Levels 1–6 are accepted; the toolbar offers 1–4.
    static func fontSize(for block: Node) -> CGFloat {
        guard block.type == "heading" else { return bodyFontSize }
        switch block.attrs["level"]?.intValue ?? 1 {
        case 1: return 32
        case 2: return 28
        case 3: return 24
        case 4: return 20
        case 5: return 18
        default: return bodyFontSize
        }
    }

    /// A custom attribute flagging a run for manual strikethrough drawing.
    /// CoreText has no strikethrough attribute CTLineDraw honours (unlike
    /// underline), so the Canvas draws it after the line — see `ProseView`.
    static let strikethroughAttributeName = NSAttributedString.Key("ProseStrikethrough")

    /// A custom attribute carrying a highlight Mark's raw `color` value. The
    /// Canvas parses it and fills the run's background before drawing glyphs.
    static let highlightAttributeName = NSAttributedString.Key("ProseHighlight")

    /// Flags a link run so the Canvas overpaints it in `linkColor` after the
    /// line is drawn — links do not carry a CoreText foreground attribute, which
    /// would leak into the shared context fill that other runs read.
    static let linkAttributeName = NSAttributedString.Key("ProseLink")

    /// The link tint — a system-blue that stays legible in light and dark.
    static let linkColor = CGColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)

    /// The accumulated CoreText styling for a run, before it becomes a font.
    /// A heading reads as bold regardless of its Marks; that block-level
    /// concern is layered in before each Mark contributes.
    static func runStyle(for marks: [Mark], blockType: String) -> RunStyle {
        var style = RunStyle()
        if blockType == "heading" {
            style.traits.insert(.traitBold)
        }
        for mark in marks {
            MarkStyles.style(for: mark.type)?.apply(mark, to: &style)
        }
        return style
    }

    static func font(for style: RunStyle, size: CGFloat) -> CTFont {
        let base = style.monospace
            ? CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
                ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
            : CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)

        guard !style.traits.isEmpty,
              let styled = CTFontCreateCopyWithSymbolicTraits(base, size, nil, style.traits, style.traits) else {
            return base
        }
        return styled
    }

    static func attributedString(for block: Node) -> NSAttributedString {
        let size = fontSize(for: block)
        let result = NSMutableAttributedString()
        for inline in block.content {
            let style = runStyle(for: inline.marks, blockType: block.type)
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font(for: style, size: size),
                // Every run draws in the context fill (the body colour, set at
                // draw time so it adapts to dark mode); links are overpainted.
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            if style.link {
                attributes[linkAttributeName] = true
            }
            if style.underline {
                attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] =
                    CTUnderlineStyle.single.rawValue
            }
            if style.strikethrough {
                attributes[strikethroughAttributeName] = true
            }
            if let highlight = style.highlight {
                attributes[highlightAttributeName] = highlight
            }
            if style.superscript != 0 {
                attributes[NSAttributedString.Key(kCTSuperscriptAttributeName as String)] = style.superscript
            }
            result.append(NSAttributedString(string: inline.text ?? "", attributes: attributes))
        }
        return result
    }

    static func emptyLineHeight(for block: Node) -> CGFloat {
        let font = font(for: runStyle(for: [], blockType: block.type), size: fontSize(for: block))
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }
}
