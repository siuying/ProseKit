struct DocRule: NodeRule {
    let type = "doc"

    func validate(_ node: Node) throws {
        try require(
            node.content.allSatisfy {
                ["paragraph", "heading", "blockquote", "bulletList", "orderedList"].contains($0.type)
            },
            "\(type) may only contain block nodes"
        )
    }
}
