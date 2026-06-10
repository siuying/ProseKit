public struct Document: Codable, Hashable, Sendable {
    public var root: Node

    public init(_ root: Node) {
        self.root = root
    }

    public init(from decoder: Decoder) throws {
        root = try Node(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try root.encode(to: encoder)
    }

    public var endPosition: Int {
        root.nodeSize - 1
    }

    public func position(ofBlockAt blockIndex: Int) -> Position? {
        guard root.content.indices.contains(blockIndex) else { return nil }
        return 1 + root.content[..<blockIndex].reduce(0) { $0 + $1.nodeSize }
    }

    public func position(ofTextInBlockAt blockIndex: Int) -> Position? {
        position(ofBlockAt: blockIndex).map { $0 + 1 }
    }
}

public typealias Position = Int
