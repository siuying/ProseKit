import CoreGraphics
import CoreText
import Foundation
import ProseModel

public struct LineFragment: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public var typographicHeight: CGFloat
    public var positionRange: Range<Position>

    public init(text: String, frame: CGRect, typographicHeight: CGFloat, positionRange: Range<Position> = 0..<0) {
        self.text = text
        self.frame = frame
        self.typographicHeight = typographicHeight
        self.positionRange = positionRange
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
}

public struct LayoutEngine: Sendable {
    public var schema: Schema
    public var characterWidth: CGFloat

    public init(schema: Schema, characterWidth: CGFloat = 10) {
        self.schema = schema
        self.characterWidth = characterWidth
    }

    public func layout(_ document: Document, width: CGFloat) throws -> LayoutBox {
        try schema.validate(document)
        var y: CGFloat = 0
        var position = 1
        let children = document.root.content.enumerated().map { index, block -> LayoutBox in
            let box = layoutLeafBlock(block, width: width, y: y, position: position, typesetID: index + 1)
            y = box.frame.maxY + 12
            position += block.nodeSize
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

    private func layoutLeafBlock(_ block: Node, width: CGFloat, y: CGFloat, position: Position, typesetID: Int) -> LayoutBox {
        let text = block.content.compactMap(\.text).joined()
        let fontSize: CGFloat = block.type == "heading" ? 28 : 17
        let lineHeight = ceil(fontSize * 1.25)
        let fragments = makeLineFragments(
            text: text,
            textStart: position + 1,
            y: y,
            width: width,
            lineHeight: lineHeight,
            characterWidth: characterWidth
        )
        let height = fragments.last?.frame.maxY ?? y
        return LayoutBox(
            kind: .leafBlock,
            node: block,
            frame: CGRect(x: 0, y: y, width: width, height: height - y),
            lineFragments: fragments,
            positionRange: position..<(position + block.nodeSize),
            typesetID: typesetID
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

        let children = document.root.content.enumerated().map { index, block -> LayoutBox in
            let range = position..<(position + block.nodeSize)
            defer {
                y += 0
                position += block.nodeSize
            }

            if let changedRange,
               !rangesIntersect(range, changedRange),
               oldChildren.indices.contains(index),
               oldChildren[index].node == block {
                var reused = oldChildren[index]
                reused.frame.origin.y = y
                reused.positionRange = range
                y = reused.frame.maxY + 12
                return reused
            }

            let box = layoutLeafBlockForStore(block, width: width, y: y, positionRange: range, typesetID: allocateTypesetID())
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

private func layoutLeafBlockForStore(
    _ block: Node,
    width: CGFloat,
    y: CGFloat,
    positionRange: Range<Position>,
    typesetID: Int
) -> LayoutBox {
    let text = block.content.compactMap(\.text).joined()
    let fontSize: CGFloat = block.type == "heading" ? 28 : 17
    let lineHeight = ceil(fontSize * 1.25)
    let fragments = makeLineFragments(
        text: text,
        textStart: positionRange.lowerBound + 1,
        y: y,
        width: width,
        lineHeight: lineHeight,
        characterWidth: 10
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

private func makeLineFragments(
    text: String,
    textStart: Position,
    y: CGFloat,
    width: CGFloat,
    lineHeight: CGFloat,
    characterWidth: CGFloat
) -> [LineFragment] {
    let characters = Array(text)
    let capacity = max(1, Int(width / characterWidth))
    guard !characters.isEmpty else {
        return [
            LineFragment(
                text: "",
                frame: CGRect(x: 0, y: y, width: width, height: lineHeight),
                typographicHeight: lineHeight,
                positionRange: textStart..<textStart
            ),
        ]
    }

    return stride(from: 0, to: characters.count, by: capacity).map { start in
        let end = min(start + capacity, characters.count)
        let lineIndex = start / capacity
        return LineFragment(
            text: String(characters[start..<end]),
            frame: CGRect(x: 0, y: y + CGFloat(lineIndex) * lineHeight, width: width, height: lineHeight),
            typographicHeight: lineHeight,
            positionRange: (textStart + start)..<(textStart + end)
        )
    }
}
