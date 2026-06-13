/// The structural rule for one Block Node type: which children and Attrs it may
/// carry. Each supported Node is a single unit; adding one (blockquote, lists,
/// codeBlock, …) means adding a `NodeRule` and listing it in `NodeRules.all`.
/// The Schema owns the cross-cutting checks (known type, text leaves, marks only
/// on text) and recurses into descendants; a rule validates one Node's own
/// content and Attrs.
protocol NodeRule: Sendable {
    var type: String { get }
    func validate(_ node: Node) throws
}

extension NodeRule {
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SchemaError.invalidDocument(message) }
    }
}

enum NodeRules {
    static let all: [any NodeRule] = [
        DocRule(), ParagraphRule(), HeadingRule(), BlockquoteRule(),
        BulletListRule(), ListItemRule(),
    ]

    static func rule(for type: String) -> (any NodeRule)? {
        all.first { $0.type == type }
    }
}
