/// The coexistence rule for one Mark type: which other Mark types it excludes.
/// Adding a Mark drops the Marks it excludes; a Mark that an existing Mark
/// excludes is not added (ProseMirror `addToSet` semantics). Most Marks exclude
/// nothing and so have no rule.
protocol MarkRule: Sendable {
    var type: String { get }
    func excludes(_ other: String) -> Bool
}

public enum MarkRules {
    static let all: [any MarkRule] = [CodeRule(), SuperscriptRule(), SubscriptRule()]

    static func rule(for type: String) -> (any MarkRule)? {
        all.first { $0.type == type }
    }

    static func excludes(_ type: String, _ other: String) -> Bool {
        rule(for: type)?.excludes(other) ?? false
    }

    /// ProseMirror `addToSet`: returns `set` with `mark` added, dropping the
    /// Marks `mark` excludes. If an existing Mark excludes `mark`, the set is
    /// returned unchanged (the new Mark cannot join, e.g. bold onto a code run).
    public static func adding(_ mark: Mark, to set: [Mark]) -> [Mark] {
        if set.contains(mark) { return set }
        var result: [Mark] = []
        for other in set {
            if excludes(mark.type, other.type) {
                continue  // the new Mark drops this one
            } else if excludes(other.type, mark.type) {
                return set  // an existing Mark forbids the new one; nothing changes
            }
            result.append(other)
        }
        result.append(mark)
        return result
    }
}
