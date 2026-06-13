public struct Node: Codable, Hashable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]
    public var content: [Node]
    public var text: String?
    public var marks: [Mark]

    public init(
        type: String,
        attrs: [String: JSONValue] = [:],
        content: [Node] = [],
        text: String? = nil,
        marks: [Mark] = []
    ) {
        self.type = type
        self.attrs = attrs
        self.content = content
        self.text = text
        self.marks = marks
    }

    public var isText: Bool { type == "text" }

    /// A *textblock* (ProseMirror's term): a non-text block whose children are
    /// inline (text) — the leaf unit CoreText typesets, e.g. paragraph, heading,
    /// code block. A container block (doc, blockquote, list, list item) holds
    /// child blocks, so this is false. An empty block counts as a textblock.
    public var isTextblock: Bool {
        !isText && content.allSatisfy(\.isText)
    }

    public var nodeSize: Int {
        if isText {
            return text?.count ?? 0
        }
        return 2 + content.reduce(0) { $0 + $1.nodeSize }
    }

    public var plainText: String {
        if isText {
            return text ?? ""
        }
        return content.map(\.plainText).joined()
    }

    public static func doc(_ content: [Node]) -> Node {
        Node(type: "doc", content: content)
    }

    public static func paragraph(_ content: [Node]) -> Node {
        Node(type: "paragraph", content: content)
    }

    public static func heading(level: Int, _ content: [Node]) -> Node {
        Node(type: "heading", attrs: ["level": .int(level)], content: content)
    }

    public static func text(_ text: String, marks: [Mark] = []) -> Node {
        Node(type: "text", text: text, marks: marks)
    }

    public static func blockquote(_ content: [Node]) -> Node {
        Node(type: "blockquote", content: content)
    }

    public func withContent(_ content: [Node]) -> Node {
        Node(type: type, attrs: attrs, content: content, text: text, marks: marks)
    }

    public func asParagraph() -> Node {
        Node(type: "paragraph", content: content)
    }

    public func asHeading(level: Int) -> Node {
        Node(type: "heading", attrs: ["level": .int(level)], content: content)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case attrs
        case content
        case text
        case marks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        attrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .attrs) ?? [:]
        content = try container.decodeIfPresent([Node].self, forKey: .content) ?? []
        text = try container.decodeIfPresent(String.self, forKey: .text)
        marks = try container.decodeIfPresent([Mark].self, forKey: .marks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if !attrs.isEmpty {
            try container.encode(attrs, forKey: .attrs)
        }
        if !content.isEmpty {
            try container.encode(content, forKey: .content)
        }
        if let text {
            try container.encode(text, forKey: .text)
        }
        if !marks.isEmpty {
            try container.encode(marks, forKey: .marks)
        }
    }
}
