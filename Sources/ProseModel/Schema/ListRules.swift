struct BulletListRule: NodeRule {
    let type = "bulletList"

    func validate(_ node: Node) throws {
        try require(!node.content.isEmpty, "bulletList must contain at least one list item")
        try require(node.content.allSatisfy { $0.type == "listItem" }, "bulletList may only contain list items")
    }
}

struct ListItemRule: NodeRule {
    let type = "listItem"

    func validate(_ node: Node) throws {
        try require(!node.content.isEmpty, "listItem must contain at least one block")
        try require(
            node.content.allSatisfy {
                ["paragraph", "heading", "blockquote", "bulletList"].contains($0.type)
            },
            "listItem may only contain block nodes"
        )
    }
}
