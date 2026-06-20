#if canImport(AppKit)
import AppKit
import CoreText
import ProseModel

@MainActor final class MacCanvasView: NSView {
    var layoutBox: LayoutBox?
    var selectionRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }
    private var windowIsKey = true {
        didSet { needsDisplay = true }
    }

    var drawsSelectionHighlight: Bool {
        !selectionRects.isEmpty
    }

    var selectionHighlightColor: NSColor {
        windowIsKey ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setWindowIsKey(_ isKey: Bool) {
        windowIsKey = isKey
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        PlatformColor.canvasBackground.setFill()
        dirtyRect.fill()
        drawSelectionHighlight(dirtyRect)
        drawCanvas(dirtyRect, in: context)
    }

    private func drawSelectionHighlight(_ dirtyRect: NSRect) {
        guard drawsSelectionHighlight else { return }
        selectionHighlightColor.setFill()
        for rect in selectionRects where rect.intersects(dirtyRect) {
            rect.fill()
        }
    }

    func drawCanvas(_ dirtyRect: CGRect, in context: CGContext) {
        guard let layoutBox else { return }
        let contentRect = dirtyRect.insetBy(dx: 0, dy: -CanvasMetrics.glyphOverhang)
        context.saveGState()
        let flipHeight = layoutBox.frame.height
        context.textMatrix = .identity
        context.translateBy(x: 0, y: flipHeight)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(PlatformColor.label.proseCGColor)
        for box in layoutBox.children {
            if box.frame.minY > contentRect.maxY { break }
            drawBox(box, in: context, contentRect: contentRect, flippedAbout: flipHeight)
        }
        context.restoreGState()
    }

    private func drawBox(
        _ box: LayoutBox,
        in context: CGContext,
        contentRect: CGRect,
        flippedAbout flipHeight: CGFloat
    ) {
        guard box.frame.intersects(contentRect) else { return }
        switch box.kind {
        case .leafBlock:
            draw(block: box, in: context, flippedAbout: flipHeight)
        case .container:
            if box.node.type == "blockquote" {
                context.saveGState()
                context.setFillColor(PlatformColor.systemGray3.proseCGColor)
                context.fill(CGRect(
                    x: box.frame.minX + 6,
                    y: flipHeight - box.frame.maxY,
                    width: 4,
                    height: box.frame.height
                ))
                context.restoreGState()
            }
            for child in box.children {
                if child.frame.minY > contentRect.maxY { break }
                drawBox(child, in: context, contentRect: contentRect, flippedAbout: flipHeight)
            }
        }
    }

    private func draw(block: LayoutBox, in context: CGContext, flippedAbout flipHeight: CGFloat) {
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
        }
    }

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
            context.saveGState()
            context.setFillColor(color.proseCGColor)
            context.fill(CGRect(
                x: lineOrigin.x + startX,
                y: lineOrigin.y - descent,
                width: endX - startX,
                height: ascent + descent
            ))
            context.restoreGState()
        }
    }

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
            let y = lineOrigin.y + CTFontGetXHeight(font) / 2
            let thickness = max(1, (CTFontGetSize(font) / 17).rounded())
            context.saveGState()
            context.setStrokeColor(PlatformColor.label.proseCGColor)
            context.setLineWidth(thickness)
            context.move(to: CGPoint(x: lineOrigin.x + startX, y: y))
            context.addLine(to: CGPoint(x: lineOrigin.x + endX, y: y))
            context.strokePath()
            context.restoreGState()
        }
    }
}

private enum CanvasMetrics {
    static let glyphOverhang: CGFloat = 2
}
#endif
