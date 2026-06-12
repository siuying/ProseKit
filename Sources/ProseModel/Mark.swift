public struct Mark: Codable, Hashable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]

    public init(type: String, attrs: [String: JSONValue] = [:]) {
        self.type = type
        self.attrs = attrs
    }

    public static let bold = Mark(type: "bold")
    public static let italic = Mark(type: "italic")
    public static let code = Mark(type: "code")
    public static let strike = Mark(type: "strike")
    public static let underline = Mark(type: "underline")
    public static let superscript = Mark(type: "superscript")
    public static let `subscript` = Mark(type: "subscript")

    public static func highlight(color: String) -> Mark {
        Mark(type: "highlight", attrs: ["color": .string(color)])
    }

    public static func link(href: String) -> Mark {
        Mark(type: "link", attrs: ["href": .string(href)])
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case attrs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        attrs = try container.decodeIfPresent([String: JSONValue].self, forKey: .attrs) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if !attrs.isEmpty {
            try container.encode(attrs, forKey: .attrs)
        }
    }
}
