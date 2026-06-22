import ProseModel

/// Translates ProseKit `Mark`s to and from y-prosemirror's `YXmlText` formatting
/// attributes (the Shared Replica wire format).
///
/// y-prosemirror keys each **non-overlapping** mark by its type name, with the
/// mark's attrs object as the value — `bold → {"bold": {}}`,
/// `link → {"link": {"href": …}}`. ProseKit's Schema asserts no self-non-excluding
/// marks, so it never *produces* a hashed (`name--XXXXXXXX`) or `ychange` key.
/// A key it does not produce — received from a richer peer — is carried through
/// unchanged so it re-emits faithfully, never stripped, skipped, or reinterpreted
/// (#70, convergence-critical).
///
/// **Invariant (deliberate boundary):** across this wire `Mark.type` is the raw
/// y-prosemirror format *key*, not necessarily a ProseKit Schema mark name. For a
/// recognised mark the two coincide (`bold`); for an opaque key they do not
/// (`comment--AbCd1234`, `ychange`). Callers must not assume `Mark.type` names a
/// Schema mark in collaborative content. (A typed opaque-mark payload that makes
/// this explicit is deferred to its own slice, ADR 0006.)
enum MarkAttributes {
    /// `marksToAttributes`: `[Mark]` → `{ markKey: markAttrs }`, the mark's type
    /// used verbatim as the key. ProseKit only authors plain mark names, but a
    /// mark carried opaquely (a `name--XXXXXXXX` hashed key, `ychange`, or an
    /// unknown name received from a richer peer) keeps its raw key here so it is
    /// re-emitted byte-faithfully and never dropped (#70, convergence-critical).
    static func attributes(for marks: [Mark]) -> [String: [String: JSONValue]] {
        var result: [String: [String: JSONValue]] = [:]
        for mark in marks {
            result[mark.type] = mark.attrs
        }
        return result
    }

    /// `attributesToMarks`: `{ markKey: markAttrs }` → `[Mark]`, sorted by key for
    /// determinism. The key is preserved verbatim as the mark type: a recognised
    /// plain name (`bold`) round-trips as itself, and a key ProseKit does not
    /// produce (hashed / `ychange` / unknown) is carried opaquely and re-emitted
    /// unchanged rather than reinterpreted or stripped.
    static func marks(from attributes: [String: [String: JSONValue]]) -> [Mark] {
        attributes
            .map { key, attrs in Mark(type: key, attrs: attrs) }
            .sorted { $0.type < $1.type }
    }
}
