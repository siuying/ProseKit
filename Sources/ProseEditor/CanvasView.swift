#if canImport(UIKit)
import CoreGraphics
import CoreText
import ProseModel
import UIKit

/// The Canvas: a Viewport-sized paint surface repositioned on scroll
/// (ADR 0002). It paints the Layout Boxes intersecting its dirty rects and
/// holds no document or geometry authority — ProseView assigns it a layout
/// tree after every relayout; selection chrome and hit-testing stay on the
/// scroll view, in content space.
@MainActor final class CanvasView: UIView {
    var layoutBox: LayoutBox?

    /// How far glyphs may paint outside their block's frame (descenders,
    /// diacritics); dirty regions widen by this on both sides.
    static let glyphOverhang: CGFloat = 2

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawCanvas(rect, in: context)
    }

    /// Paints the Layout Boxes intersecting the dirty region. `rect` is
    /// Canvas-local; blocks live in content space, offset by the Canvas's
    /// origin (the contentOffset). Internal so the culling-equivalence
    /// rendering test can drive it directly.
    func drawCanvas(_ rect: CGRect, in context: CGContext) {
        guard let layoutBox else { return }
        let origin = frame.origin
        // Outset for glyph overhang: descenders of a block ending just above
        // the dirty region still paint into it.
        let contentRect = rect
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: 0, dy: -Self.glyphOverhang)
        context.saveGState()
        // CoreText draws in a bottom-left coordinate space; flip to UIKit's
        // about the layout height, then shift content space into the Canvas.
        let flipHeight = layoutBox.frame.height
        context.textMatrix = .identity
        context.translateBy(x: -origin.x, y: -origin.y)
        context.translateBy(x: 0, y: flipHeight)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.label.cgColor)
        for box in layoutBox.children {
            // Boxes are y-ordered; everything past the dirty rect is clean.
            if box.frame.minY > contentRect.maxY { break }
            drawBox(box, parent: layoutBox, in: context, contentRect: contentRect, flippedAbout: flipHeight)
        }
        context.restoreGState()
    }

    /// Draws one box: a leaf typesets its line fragments; a container paints its
    /// decoration (the blockquote rule) then recurses into its children. Boxes
    /// outside the dirty region are skipped.
    private func drawBox(
        _ box: LayoutBox,
        parent: LayoutBox?,
        in context: CGContext,
        contentRect: CGRect,
        flippedAbout flipHeight: CGFloat,
        checkedTaskItem: Bool = false
    ) {
        guard box.frame.intersects(contentRect) else { return }
        switch box.kind {
        case .leafBlock:
            draw(block: box, in: context, flippedAbout: flipHeight, checkedTaskItem: checkedTaskItem)
        case .container:
            drawContainerDecoration(box, parent: parent, in: context, flippedAbout: flipHeight)
            let childCheckedTaskItem = checkedTaskItem
                || (box.node.type == "taskItem" && box.node.attrs["checked"]?.boolValue == true)
            for child in box.children {
                if child.frame.minY > contentRect.maxY { break }
                drawBox(
                    child,
                    parent: box,
                    in: context,
                    contentRect: contentRect,
                    flippedAbout: flipHeight,
                    checkedTaskItem: childCheckedTaskItem
                )
            }
        }
    }

    /// Container decorations drawn in content space (flipped about the layout
    /// height like the glyphs). Slice 01: the blockquote's vertical rule down
    /// its indent band.
    private func drawContainerDecoration(_ box: LayoutBox, parent: LayoutBox?, in context: CGContext, flippedAbout flipHeight: CGFloat) {
        switch box.node.type {
        case "blockquote":
            let rule = CGRect(
                x: box.frame.minX + 6,
                y: flipHeight - box.frame.maxY,
                width: 4,
                height: box.frame.height
            )
            context.saveGState()
            context.setFillColor(UIColor.systemGray3.cgColor)
            context.fill(rule)
            context.restoreGState()
        case "listItem":
            if parent?.node.type == "orderedList" {
                drawOrderedMarker(for: box, parent: parent, in: context, flippedAbout: flipHeight)
            } else {
                // A bullet disc centred on the item's first line, in the indent
                // band to the left of the text.
                let radius: CGFloat = 2.75
                let lineCenter = box.frame.minY + firstLineCenterOffset(in: box)
                let center = CGPoint(x: box.frame.minX + 12, y: flipHeight - lineCenter)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.saveGState()
                context.setFillColor(UIColor.label.cgColor)
                context.fillEllipse(in: rect)
                context.restoreGState()
            }
        case "taskItem":
            drawTaskCheckbox(for: box, in: context, flippedAbout: flipHeight)
        default:
            break
        }
    }

    private func drawOrderedMarker(for box: LayoutBox, parent: LayoutBox?, in context: CGContext, flippedAbout flipHeight: CGFloat) {
        guard let parent,
              let index = parent.children.firstIndex(where: { $0.positionRange == box.positionRange }) else {
            return
        }
        let start = parent.node.attrs["start"]?.intValue ?? 1
        let marker = "\(start + index)."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: marker, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let lineCenter = box.frame.minY + firstLineCenterOffset(in: box)
        context.saveGState()
        context.textPosition = CGPoint(x: box.frame.minX + 20 - width, y: flipHeight - lineCenter + 6)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawTaskCheckbox(for box: LayoutBox, in context: CGContext, flippedAbout flipHeight: CGFloat) {
        let size: CGFloat = 15
        let lineCenter = box.frame.minY + firstLineCenterOffset(in: box)
        let rect = CGRect(
            x: box.frame.minX + 5,
            y: flipHeight - lineCenter - size / 2,
            width: size,
            height: size
        )
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        let checked = box.node.attrs["checked"]?.boolValue == true
        context.saveGState()
        if checked {
            context.addPath(path)
            context.clip()
            let colors = [
                UIColor.systemGreen.cgColor,
                UIColor.systemTeal.cgColor,
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.maxY),
                    end: CGPoint(x: rect.maxX, y: rect.minY),
                    options: []
                )
            }
            context.resetClip()
            context.addPath(path)
            context.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1)
            context.strokePath()

            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(2.1)
            context.move(to: CGPoint(x: rect.minX + 3.2, y: rect.minY + size * 0.45))
            context.addLine(to: CGPoint(x: rect.minX + size * 0.43, y: rect.minY + size * 0.28))
            context.addLine(to: CGPoint(x: rect.maxX - 2.4, y: rect.minY + size * 0.72))
            context.strokePath()
        } else {
            context.addPath(path)
            context.setStrokeColor(UIColor.tertiaryLabel.cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// The vertical centre of a container's first line, relative to the
    /// container's top — descends to the first leaf's first fragment so a marker
    /// aligns with the text even when the first block is a heading.
    private func firstLineCenterOffset(in box: LayoutBox) -> CGFloat {
        var node = box
        var offset: CGFloat = 0
        while node.kind == .container, let first = node.children.first {
            offset += first.frame.minY - node.frame.minY
            node = first
        }
        let lineHeight = node.lineFragments.first?.frame.height ?? 20
        return offset + lineHeight / 2
    }

    /// The content-space region an edit can have moved: the changed blocks'
    /// frames, extended to the document bottom when heights shift everything
    /// below. A wrong-too-big rect costs a repaint; a wrong-too-small rect
    /// leaves stale pixels, so every uncertain case falls back to `fallback`.
    static func editDirtyRect(
        from previous: LayoutBox?,
        to current: LayoutBox?,
        changedRange: Range<Position>?,
        fallback: CGRect
    ) -> CGRect {
        guard let previous, let current, let changedRange else { return fallback }
        // A collapsed range still names the edited spot (e.g. a no-op
        // command); widen it so the containing block is found.
        let range = changedRange.isEmpty
            ? changedRange.lowerBound..<(changedRange.lowerBound + 1)
            : changedRange
        var dirty: CGRect = .null
        for box in current.children {
            if box.positionRange.lowerBound >= range.upperBound { break }
            guard rangesIntersect(box.positionRange, range) else { continue }
            dirty = dirty.union(box.frame)
        }
        guard !dirty.isNull else { return fallback }

        // When total height or block count changes, every block below the
        // edit moved; both the old and new extent must repaint.
        if previous.frame.height != current.frame.height
            || previous.children.count != current.children.count {
            let bottom = max(previous.frame.maxY, current.frame.maxY)
            dirty = CGRect(
                x: 0, y: dirty.minY,
                width: max(fallback.width, dirty.width),
                height: bottom - dirty.minY
            )
        }
        // Full-width strip (fragment frames can be narrower than the view),
        // outset for glyph overhang at the strip edges.
        return CGRect(
            x: 0, y: dirty.minY,
            width: max(fallback.width, dirty.width),
            height: dirty.height
        ).insetBy(dx: 0, dy: -glyphOverhang)
    }

    private func draw(block: LayoutBox, in context: CGContext, flippedAbout flipHeight: CGFloat, checkedTaskItem: Bool = false) {
        if checkedTaskItem {
            context.saveGState()
            context.setAlpha(0.48)
        }
        for fragment in block.lineFragments {
            guard let typeset = fragment.typesetLine else { continue }
            let baseline = block.frame.minY + fragment.frame.minY + typeset.ascent
            let origin = CGPoint(
                x: block.frame.minX + fragment.frame.minX,
                y: flipHeight - baseline
            )
            drawHighlights(for: typeset.line, lineOrigin: origin, in: context)
            context.textPosition = origin
            CTLineDraw(typeset.line, context)
            drawLinkTint(for: typeset.line, lineOrigin: origin, in: context)
            drawStrikethrough(for: typeset.line, lineOrigin: origin, in: context)
            if checkedTaskItem {
                drawTaskCompletionStrike(for: fragment, lineOrigin: origin, in: context)
            }
        }
        if checkedTaskItem {
            context.restoreGState()
        }
    }

    private func drawTaskCompletionStrike(for fragment: LineFragment, lineOrigin: CGPoint, in context: CGContext) {
        guard fragment.frame.width > 0 else { return }
        context.saveGState()
        context.setAlpha(0.8)
        context.setStrokeColor(UIColor.label.cgColor)
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        let y = lineOrigin.y + fragment.typographicHeight * 0.28
        context.move(to: CGPoint(x: lineOrigin.x, y: y))
        context.addLine(to: CGPoint(x: lineOrigin.x + fragment.frame.width, y: y))
        context.strokePath()
        context.restoreGState()
    }

    /// Recolours link runs in the link tint after the line is drawn in the body
    /// colour. Links don't carry an explicit CoreText foreground (that would leak
    /// into the shared context fill that foreground-from-context runs read); the
    /// tint is overpainted here, like highlight and strikethrough.
    private func drawLinkTint(for line: CTLine, lineOrigin: CGPoint, in context: CGContext) {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[BlockStyle.linkAttributeName] != nil else { continue }
            context.saveGState()
            context.setFillColor(BlockStyle.linkColor)
            context.textPosition = lineOrigin
            CTRunDraw(run, context, CFRange(location: 0, length: 0))
            context.restoreGState()
        }
    }

    /// Fills the background behind each run carrying a highlight colour, drawn
    /// before the glyphs. The raw `color` value is parsed here (not at layout
    /// time) so dark-mode palette colours resolve against the current traits;
    /// an unparseable value draws nothing, the Mark surviving regardless.
    private func drawHighlights(for line: CTLine, lineOrigin: CGPoint, in context: CGContext) {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[BlockStyle.highlightAttributeName] as? String,
                  let color = HighlightColor.color(for: value) else { continue }
            let stringRange = CTRunGetStringRange(run)
            let startX = CTLineGetOffsetForStringIndex(line, stringRange.location, nil)
            let endX = CTLineGetOffsetForStringIndex(line, stringRange.location + stringRange.length, nil)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
            let rect = CGRect(
                x: lineOrigin.x + startX,
                y: lineOrigin.y - descent,
                width: endX - startX,
                height: ascent + descent
            )
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.fill(rect)
            context.restoreGState()
        }
    }

    /// CoreText draws underline but not strikethrough, so each run flagged by
    /// `BlockStyle.strikethroughAttributeName` gets a manual stroke through the
    /// x-height. Run geometry comes from the same CTLine the glyphs drew, so the
    /// stroke stays exactly aligned with what was typeset.
    private func drawStrikethrough(for line: CTLine, lineOrigin: CGPoint, in context: CGContext) {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[BlockStyle.strikethroughAttributeName] != nil,
                  let font = attributes[kCTFontAttributeName as String].map({ $0 as! CTFont }) else {
                continue
            }
            let stringRange = CTRunGetStringRange(run)
            let startX = CTLineGetOffsetForStringIndex(line, stringRange.location, nil)
            let endX = CTLineGetOffsetForStringIndex(line, stringRange.location + stringRange.length, nil)
            // A line through the middle of lowercase glyphs.
            let y = lineOrigin.y + CTFontGetXHeight(font) / 2
            let thickness = max(1, (CTFontGetSize(font) / 17).rounded())
            context.saveGState()
            // Match the glyph colour set in drawCanvas (foreground-from-context).
            context.setStrokeColor(UIColor.label.cgColor)
            context.setLineWidth(thickness)
            context.move(to: CGPoint(x: lineOrigin.x + startX, y: y))
            context.addLine(to: CGPoint(x: lineOrigin.x + endX, y: y))
            context.strokePath()
            context.restoreGState()
        }
    }
}
#endif
