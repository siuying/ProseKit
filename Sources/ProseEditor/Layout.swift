import CoreGraphics
import CoreText
import Foundation
import ProseModel

/// A typeset CoreText line plus the bookkeeping needed to map between the
/// block's typeset string (UTF-16 indices) and document Positions.
/// CTLine is immutable, so sharing it across isolation domains is safe.
public struct TypesetLine: @unchecked Sendable, Equatable {
    public let line: CTLine
    public let ascent: CGFloat
    /// Range in the block attributed string's UTF-16 view that this line covers.
    public let utf16Range: Range<Int>

    public static func == (lhs: TypesetLine, rhs: TypesetLine) -> Bool {
        lhs.line === rhs.line
    }
}

public struct LineFragment: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public var typographicHeight: CGFloat
    public var positionRange: Range<Position>
    public var typesetLine: TypesetLine?

    public init(
        text: String,
        frame: CGRect,
        typographicHeight: CGFloat,
        positionRange: Range<Position> = 0..<0,
        typesetLine: TypesetLine? = nil
    ) {
        self.text = text
        self.frame = frame
        self.typographicHeight = typographicHeight
        self.positionRange = positionRange
        self.typesetLine = typesetLine
    }
}

public struct LayoutBox: Equatable, Sendable {
    public enum Kind: Sendable {
        case container
        case leafBlock
    }

    public var kind: Kind
    public var node: Node
    public var frame: CGRect
    public var children: [LayoutBox]
    public var lineFragments: [LineFragment]
    public var positionRange: Range<Position>
    public var typesetID: Int

    public init(
        kind: Kind,
        node: Node,
        frame: CGRect,
        children: [LayoutBox] = [],
        lineFragments: [LineFragment] = [],
        positionRange: Range<Position> = 0..<0,
        typesetID: Int = 0
    ) {
        self.kind = kind
        self.node = node
        self.frame = frame
        self.children = children
        self.lineFragments = lineFragments
        self.positionRange = positionRange
        self.typesetID = typesetID
    }

    func moved(toY y: CGFloat, positionRange range: Range<Position>) -> LayoutBox {
        var copy = self
        copy.frame.origin.y = y
        copy.positionRange = range
        return copy
    }
}

/// The vertical gap stacked between consecutive Layout Boxes.
let blockSpacing: CGFloat = 12

/// One-shot layout: a fresh `IncrementalLayoutStore` with no previous layout
/// to reuse. The single stacking loop lives in the store.
public struct LayoutEngine: Sendable {
    public var schema: Schema

    public init(schema: Schema) {
        self.schema = schema
    }

    public func layout(_ document: Document, width: CGFloat) throws -> LayoutBox {
        var store = IncrementalLayoutStore(schema: schema, width: width)
        return try store.layout(document)
    }
}

/// Block i's position range from the Document's block index — O(1), unlike
/// `node.nodeSize`, which re-counts the block's text on every call. Blocks
/// tile the position space, so the range ends where the next block starts.
private func blockRange(at index: Int, in document: Document) -> Range<Position> {
    let start = document.position(ofBlockAt: index) ?? 1
    let end = index + 1 < document.blockCount
        ? (document.position(ofBlockAt: index + 1) ?? start)
        : document.endPosition
    return start..<end
}

public struct IncrementalLayoutStore: Sendable {
    public var schema: Schema
    public var width: CGFloat

    private var previous: LayoutBox?
    private var previousWidth: CGFloat
    private var nextTypesetID: Int

    public init(schema: Schema, width: CGFloat) {
        self.schema = schema
        self.width = width
        self.previousWidth = width
        self.nextTypesetID = 1
    }

    /// Relayouts the document, re-typesetting only the blocks the Changed
    /// Range touches. Per-block work for untouched blocks must stay O(1) —
    /// no `nodeSize` (re-counts the block's text) and no `node ==` content
    /// comparison (the Changed Range is authoritative; the rendering-
    /// equivalence tests pin that trust). Issue 07: the previous walk made
    /// every keystroke O(document).
    public mutating func layout(_ document: Document, changedRange: Range<Position>? = nil) throws -> LayoutBox {
        let oldChildren = previous?.children ?? []
        // A width change invalidates every cached typeset; reuse is only
        // sound against a previous layout at the same width.
        let reuseRange = (previous != nil && width == previousWidth) ? changedRange : nil
        if reuseRange == nil {
            try schema.validate(document)
        }
        let blockCount = document.blockCount
        let tailIndexDelta = oldChildren.count - blockCount

        var children: [LayoutBox] = []
        children.reserveCapacity(blockCount)
        var y: CGFloat = 0
        for index in 0..<blockCount {
            let range = blockRange(at: index, in: document)

            if let reuseRange, !rangesIntersect(range, reuseRange) {
                // Blocks past the edit keep their old layout but sit at a
                // shifted index when the edit split or joined blocks.
                let oldIndex = range.lowerBound >= reuseRange.upperBound ? index + tailIndexDelta : index
                if oldChildren.indices.contains(oldIndex) {
                    let old = oldChildren[oldIndex]
                    if old.frame.origin.y == y, old.positionRange == range {
                        children.append(old)
                    } else {
                        children.append(old.moved(toY: y, positionRange: range))
                    }
                    y += old.frame.height + blockSpacing
                    continue
                }
            }

            let block = document.root.content[index]
            if reuseRange != nil {
                try schema.validate(block: block)
            }
            let box = typesetLeafBlock(block, width: width, y: y, positionRange: range, typesetID: allocateTypesetID())
            y = box.frame.maxY + blockSpacing
            children.append(box)
        }

        let root = LayoutBox(
            kind: .container,
            node: document.root,
            frame: CGRect(x: 0, y: 0, width: width, height: children.last?.frame.maxY ?? 0),
            children: children,
            positionRange: 0..<(document.endPosition + 1)
        )
        previous = root
        previousWidth = width
        return root
    }

    private mutating func allocateTypesetID() -> Int {
        defer { nextTypesetID += 1 }
        return nextTypesetID
    }
}

func rangesIntersect(_ lhs: Range<Position>, _ rhs: Range<Position>) -> Bool {
    lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
}

/// The x-origin of a line under a block's `textAlign` (Q9.2). Left, justify,
/// an absent value, and any value we don't recognise all flush left, so an
/// unknown alignment degrades in rendering, never in data (ADR 0005).
private func alignedOriginX(_ alignment: String?, lineWidth: CGFloat, width: CGFloat) -> CGFloat {
    switch alignment {
    case "right": return max(0, width - lineWidth)
    case "center": return max(0, (width - lineWidth) / 2)
    default: return 0
    }
}

private func typesetLeafBlock(
    _ block: Node,
    width: CGFloat,
    y: CGFloat,
    positionRange: Range<Position>,
    typesetID: Int
) -> LayoutBox {
    let fragments = typesetLineFragments(
        for: block,
        textStart: 1,
        y: 0,
        width: width
    )
    return LayoutBox(
        kind: .leafBlock,
        node: block,
        frame: CGRect(x: 0, y: y, width: width, height: fragments.last?.frame.maxY ?? 0),
        lineFragments: fragments,
        positionRange: positionRange,
        typesetID: typesetID
    )
}

private func typesetLineFragments(
    for block: Node,
    textStart: Position,
    y: CGFloat,
    width: CGFloat
) -> [LineFragment] {
    let attributed = BlockStyle.attributedString(for: block)
    let text = attributed.string

    guard !text.isEmpty else {
        let height = BlockStyle.emptyLineHeight(for: block)
        return [
            LineFragment(
                text: "",
                frame: CGRect(x: 0, y: y, width: 0, height: height),
                typographicHeight: height,
                positionRange: textStart..<textStart
            ),
        ]
    }

    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    let alignment = block.attrs["textAlign"]?.stringValue
    let utf16Count = text.utf16.count
    var fragments: [LineFragment] = []
    var lineY = y
    var utf16Start = 0
    var characterStart = 0
    var startIndex = text.startIndex

    while utf16Start < utf16Count {
        let suggested = CTTypesetterSuggestLineBreak(typesetter, utf16Start, Double(max(width, 1)))
        let length = max(1, suggested)
        var line = CTTypesetterCreateLine(typesetter, CFRange(location: utf16Start, length: length))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        var lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ceil(ascent + descent + leading)

        let utf16End = utf16Start + length
        // Justified text stretches every line but the last to the full width;
        // CTLine doesn't justify on its own (a known CoreText gotcha).
        if alignment == "justify", utf16End < utf16Count,
           let justified = CTLineCreateJustifiedLine(line, 1, Double(width)) {
            line = justified
            lineWidth = width
        }
        let originX = alignedOriginX(alignment, lineWidth: lineWidth, width: width)
        let endIndex = characterIndex(forUTF16Offset: utf16End, in: text)
        let characterCount = text.distance(from: startIndex, to: endIndex)

        fragments.append(LineFragment(
            text: String(text[startIndex..<endIndex]),
            frame: CGRect(x: originX, y: lineY, width: lineWidth, height: height),
            typographicHeight: height,
            positionRange: (textStart + characterStart)..<(textStart + characterStart + characterCount),
            typesetLine: TypesetLine(line: line, ascent: ascent, utf16Range: utf16Start..<utf16End)
        ))

        lineY += height
        utf16Start = utf16End
        characterStart += characterCount
        startIndex = endIndex
    }

    return fragments
}

/// Maps a UTF-16 offset into `text` to a `String.Index`, rounding down to the
/// nearest character boundary when the offset lands inside a grapheme cluster.
func characterIndex(forUTF16Offset offset: Int, in text: String) -> String.Index {
    let clamped = max(0, min(offset, text.utf16.count))
    var utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
    while utf16Index > text.utf16.startIndex {
        if let index = String.Index(utf16Index, within: text) {
            return index
        }
        utf16Index = text.utf16.index(before: utf16Index)
    }
    return text.startIndex
}
