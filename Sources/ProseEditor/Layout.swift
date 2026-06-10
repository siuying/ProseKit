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

    public init(
        kind: Kind,
        node: Node,
        frame: CGRect,
        children: [LayoutBox] = [],
        lineFragments: [LineFragment] = []
    ) {
        self.kind = kind
        self.node = node
        self.frame = frame
        self.children = children
        self.lineFragments = lineFragments
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
        let children = document.root.content.map { block -> LayoutBox in
            let box = layoutLeafBlock(block, width: width, y: y)
            y = box.frame.maxY + 12
            return box
        }
        let height = children.last.map(\.frame.maxY) ?? 0
        return LayoutBox(
            kind: .container,
            node: document.root,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            children: children
        )
    }

    private func layoutLeafBlock(_ block: Node, width: CGFloat, y: CGFloat) -> LayoutBox {
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
            lineFragments: [fragment]
        )
    }
}
