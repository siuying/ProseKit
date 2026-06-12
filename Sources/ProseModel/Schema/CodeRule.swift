/// Inline `code` excludes every other Mark: a code span carries no other
/// formatting (Q9.4). Adding code drops the run's other Marks; adding another
/// Mark to a code run is rejected.
struct CodeRule: MarkRule {
    let type = "code"

    func excludes(_ other: String) -> Bool {
        other != type
    }
}
