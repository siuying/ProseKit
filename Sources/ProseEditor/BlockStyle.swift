import CoreGraphics
import CoreText
import Foundation
import ProseModel

/// Resolves marks and block types to concrete CoreText attributes. Layout and
/// drawing must both go through this so measured text is exactly drawn text.
enum BlockStyle {
    static func fontSize(for blockType: String) -> CGFloat {
        blockType == "heading" ? 28 : 17
    }

    static func font(for marks: [Mark], blockType: String) -> CTFont {
        let size = fontSize(for: blockType)
        let base = marks.contains(.code)
            ? CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
                ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
            : CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)

        var traits: CTFontSymbolicTraits = []
        if marks.contains(.bold) || blockType == "heading" {
            traits.insert(.traitBold)
        }
        if marks.contains(.italic) {
            traits.insert(.traitItalic)
        }
        guard !traits.isEmpty,
              let styled = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) else {
            return base
        }
        return styled
    }

    static func attributedString(for block: Node) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in block.content {
            result.append(NSAttributedString(
                string: inline.text ?? "",
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String):
                        font(for: inline.marks, blockType: block.type),
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String):
                        true,
                ]
            ))
        }
        return result
    }

    static func emptyLineHeight(for blockType: String) -> CGFloat {
        let font = font(for: [], blockType: blockType)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }
}
