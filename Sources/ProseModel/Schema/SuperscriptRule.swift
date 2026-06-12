/// Superscript and subscript are mutually exclusive (Q9.5).
struct SuperscriptRule: MarkRule {
    let type = "superscript"

    func excludes(_ other: String) -> Bool {
        other == "subscript"
    }
}

struct SubscriptRule: MarkRule {
    let type = "subscript"

    func excludes(_ other: String) -> Bool {
        other == "superscript"
    }
}
