import CoreGraphics
import CoreText
import Foundation
import ProseModel

public struct LineFragment: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public var typographicHeight: CGFloat

    public init(text: String, frame: CGRect, typographicHeight: CGFloat) {
        self.text = text
        self.frame = frame
        self.typographicHeight = typographicHeight
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

    public init(schema: Schema) {
        self.schema = schema
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
        let fragment = LineFragment(
            text: text,
            frame: CGRect(x: 0, y: y, width: width, height: lineHeight),
            typographicHeight: lineHeight
        )
        return LayoutBox(
            kind: .leafBlock,
            node: block,
            frame: CGRect(x: 0, y: y, width: width, height: lineHeight),
            lineFragments: [fragment],
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
    return LayoutBox(
        kind: .leafBlock,
        node: block,
        frame: CGRect(x: 0, y: y, width: width, height: lineHeight),
        lineFragments: [
            LineFragment(
                text: text,
                frame: CGRect(x: 0, y: y, width: width, height: lineHeight),
                typographicHeight: lineHeight
            ),
        ],
        positionRange: positionRange,
        typesetID: typesetID
    )
}
