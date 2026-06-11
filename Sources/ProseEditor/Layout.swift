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

    func shifted(toY y: CGFloat, positionRange range: Range<Position>) -> LayoutBox {
        let deltaY = y - frame.origin.y
        let deltaPosition = range.lowerBound - positionRange.lowerBound
        if deltaY == 0, deltaPosition == 0 {
            return self
        }
        var copy = self
        copy.frame.origin.y = y
        copy.positionRange = range
        copy.lineFragments = lineFragments.map { fragment in
            var shifted = fragment
            shifted.frame.origin.y += deltaY
            shifted.positionRange = (fragment.positionRange.lowerBound + deltaPosition)
                ..< (fragment.positionRange.upperBound + deltaPosition)
            return shifted
        }
        return copy
    }
}

public struct LayoutEngine: Sendable {
    public var schema: Schema

    public init(schema: Schema) {
        self.schema = schema
    }

    public func layout(_ document: Document, width: CGFloat) throws -> LayoutBox {
        try schema.validate(document)
        var y: CGFloat = 0
        var position = 1
        let children = document.root.content.enumerated().map { index, block -> LayoutBox in
            let range = position..<(position + block.nodeSize)
            let box = typesetLeafBlock(block, width: width, y: y, positionRange: range, typesetID: index + 1)
            y = box.frame.maxY + 12
            position = range.upperBound
            return box
        }
        let height = children.last.map(\.frame.maxY) ?? 0
        return LayoutBox(
            kind: .container,
            node: document.root,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            children: children,
            positionRange: 0..<document.root.nodeSize
        )
    }
}

public struct IncrementalLayoutStore: Sendable {
    public var schema: Schema
    public var width: CGFloat

    private var previous: LayoutBox?
    private var nextTypesetID: Int

    public init(schema: Schema, width: CGFloat) {
        self.schema = schema
        self.width = width
        self.nextTypesetID = 1
    }

    public mutating func layout(_ document: Document, changedRange: Range<Position>? = nil) throws -> LayoutBox {
        try schema.validate(document)
        var y: CGFloat = 0
        var position = 1
        let oldChildren = previous?.children ?? []
        let tailIndexDelta = oldChildren.count - document.root.content.count

        let children = document.root.content.enumerated().map { index, block -> LayoutBox in
            let range = position..<(position + block.nodeSize)
            defer { position = range.upperBound }
            let oldIndex: Int
            if let changedRange, range.lowerBound >= changedRange.upperBound {
                oldIndex = index + tailIndexDelta
            } else {
                oldIndex = index
            }

            if let changedRange,
               !rangesIntersect(range, changedRange),
               oldChildren.indices.contains(oldIndex),
               oldChildren[oldIndex].node == block {
                let reused = oldChildren[oldIndex].shifted(toY: y, positionRange: range)
                y = reused.frame.maxY + 12
                return reused
            }

            let box = typesetLeafBlock(block, width: width, y: y, positionRange: range, typesetID: allocateTypesetID())
            y = box.frame.maxY + 12
            return box
        }

        let root = LayoutBox(
            kind: .container,
            node: document.root,
            frame: CGRect(x: 0, y: 0, width: width, height: children.last?.frame.maxY ?? 0),
            children: children,
            positionRange: 0..<document.root.nodeSize
        )
        previous = root
        return root
    }

    private mutating func allocateTypesetID() -> Int {
        defer { nextTypesetID += 1 }
        return nextTypesetID
    }
}

private func rangesIntersect(_ lhs: Range<Position>, _ rhs: Range<Position>) -> Bool {
    lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
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
        textStart: positionRange.lowerBound + 1,
        y: y,
        width: width
    )
    return LayoutBox(
        kind: .leafBlock,
        node: block,
        frame: CGRect(x: 0, y: y, width: width, height: (fragments.last?.frame.maxY ?? y) - y),
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
        let height = BlockStyle.emptyLineHeight(for: block.type)
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
    let utf16Count = text.utf16.count
    var fragments: [LineFragment] = []
    var lineY = y
    var utf16Start = 0
    var characterStart = 0
    var startIndex = text.startIndex

    while utf16Start < utf16Count {
        let suggested = CTTypesetterSuggestLineBreak(typesetter, utf16Start, Double(max(width, 1)))
        let length = max(1, suggested)
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: utf16Start, length: length))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ceil(ascent + descent + leading)

        let utf16End = utf16Start + length
        let endIndex = characterIndex(forUTF16Offset: utf16End, in: text)
        let characterCount = text.distance(from: startIndex, to: endIndex)

        fragments.append(LineFragment(
            text: String(text[startIndex..<endIndex]),
            frame: CGRect(x: 0, y: lineY, width: lineWidth, height: height),
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
