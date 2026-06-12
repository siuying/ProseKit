struct HeadingRule: NodeRule {
    let type = "heading"

    func validate(_ node: Node) throws {
        try require(node.content.allSatisfy(\.isText), "heading may only contain text")
        let level = node.attrs["level"]?.intValue
        try require((1...6).contains(level ?? 0), "heading requires a level from 1 through 6")
    }
}
