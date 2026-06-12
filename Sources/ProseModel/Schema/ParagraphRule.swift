struct ParagraphRule: NodeRule {
    let type = "paragraph"

    func validate(_ node: Node) throws {
        try require(node.content.allSatisfy(\.isText), "paragraph may only contain text")
    }
}
