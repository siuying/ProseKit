public struct Schema: Sendable {
    public var nodes: Set<String>
    /// The Mark types we render with a hook. No longer a validation gate:
    /// unknown Marks are preserved, not rejected (ADR 0006). It enumerates the
    /// supported set for consumers like the toolbar's active-state (a later slice).
    public var marks: Set<String>

    public init(nodes: Set<String>, marks: Set<String>) {
        self.nodes = nodes
        self.marks = marks
    }

    public static let slice1 = Schema(
        nodes: ["doc", "paragraph", "heading", "blockquote", "bulletList", "orderedList", "listItem", "taskList", "taskItem", "text"],
        marks: ["bold", "italic", "code", "strike", "underline", "highlight", "superscript", "subscript", "link"]
    )

    public func validate(_ document: Document) throws {
        guard document.root.type == "doc" else {
            throw SchemaError.invalidDocument("root node must be doc")
        }
        try validate(document.root)
    }

    /// Validates a single block subtree. Incremental relayout validates only
    /// the blocks an edit touched; re-validating the whole document would put
    /// an O(document) walk back on every keystroke.
    public func validate(block: Node) throws {
        try validate(block)
    }

    private func validate(_ node: Node) throws {
        guard nodes.contains(node.type) else {
            throw SchemaError.invalidDocument("unknown node type \(node.type)")
        }

        if node.isText {
            guard node.content.isEmpty else {
                throw SchemaError.invalidDocument("text nodes cannot contain child nodes")
            }
            // Unknown mark types are preserved, not rejected: a Tiptap document
            // may carry marks outside our supported set, and ADR 0006 keeps them
            // in the model (rendered as plain text) so re-export is byte-faithful.
            return
        }

        guard node.marks.isEmpty else {
            throw SchemaError.invalidDocument("marks are only allowed on text nodes")
        }

        try NodeRules.rule(for: node.type)?.validate(node)

        for child in node.content {
            try validate(child)
        }
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
