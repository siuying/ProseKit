public struct Schema: Sendable {
    public var nodes: Set<String>
    public var marks: Set<String>

    public init(nodes: Set<String>, marks: Set<String>) {
        self.nodes = nodes
        self.marks = marks
    }

    public static let slice1 = Schema(
        nodes: ["doc", "paragraph", "heading", "text"],
        marks: ["bold", "italic", "code"]
    )

    public func validate(_ document: Document) throws {
        try validate(document.root, parent: nil)
        guard document.root.type == "doc" else {
            throw SchemaError.invalidDocument("root node must be doc")
        }
    }

    private func validate(_ node: Node, parent: Node?) throws {
        guard nodes.contains(node.type) else {
            throw SchemaError.invalidDocument("unknown node type \(node.type)")
        }

        if node.isText {
            guard node.content.isEmpty else {
                throw SchemaError.invalidDocument("text nodes cannot contain child nodes")
            }
            for mark in node.marks where !marks.contains(mark.type) {
                throw SchemaError.invalidDocument("unknown mark type \(mark.type)")
            }
            return
        }

        guard node.marks.isEmpty else {
            throw SchemaError.invalidDocument("marks are only allowed on text nodes")
        }

        switch node.type {
        case "doc":
            try require(node.content.allSatisfy { $0.type == "paragraph" || $0.type == "heading" }, "\(node.type) may only contain block nodes")
        case "paragraph":
            try require(node.content.allSatisfy(\.isText), "paragraph may only contain text")
        case "heading":
            try require(node.content.allSatisfy(\.isText), "heading may only contain text")
            let level = node.attrs["level"]?.intValue
            try require((1...6).contains(level ?? 0), "heading requires a level from 1 through 6")
        default:
            break
        }

        for child in node.content {
            try validate(child, parent: node)
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SchemaError.invalidDocument(message) }
    }
}

public enum SchemaError: Error, Equatable, CustomStringConvertible {
    case invalidDocument(String)

    public var description: String {
        switch self {
        case .invalidDocument(let message):
            message
        }
    }
}
