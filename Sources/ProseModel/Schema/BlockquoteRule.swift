struct BlockquoteRule: NodeRule {
    let type = "blockquote"

    func validate(_ node: Node) throws {
        try require(!node.content.isEmpty, "blockquote must contain at least one block")
        try require(
            node.content.allSatisfy { $0.type == "paragraph" || $0.type == "heading" || $0.type == "blockquote" },
            "blockquote may only contain block nodes"
        )
    }
}
