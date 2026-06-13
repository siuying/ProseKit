struct DocRule: NodeRule {
    let type = "doc"

    func validate(_ node: Node) throws {
        try require(
            node.content.allSatisfy { $0.type == "paragraph" || $0.type == "heading" || $0.type == "blockquote" },
            "\(type) may only contain block nodes"
        )
    }
}
