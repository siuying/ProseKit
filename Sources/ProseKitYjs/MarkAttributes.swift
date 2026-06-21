import ProseModel

/// Translates ProseKit `Mark`s to and from y-prosemirror's `YXmlText` formatting
/// attributes (the Shared Replica wire format).
///
/// y-prosemirror keys each **non-overlapping** mark by its type name, with the
/// mark's attrs object as the value — `bold → {"bold": {}}`,
/// `link → {"link": {"href": …}}`. ProseKit's Schema asserts no self-non-excluding
/// marks, so the hashed-key (`name--XXXXXXXX`) path is never *produced*; a hashed
/// or `ychange` key *received* from a richer peer is still read without crashing
/// (the `--XXXXXXXX` suffix is stripped, `ychange` is skipped). Byte-faithful
/// preservation of keys we do not understand is the Opaque Round-trip slice (#70).
enum MarkAttributes {
    /// Reserved by y-prosemirror for snapshot diff rendering — never emitted, skipped on read.
    static let reservedKey = "ychange"

    /// `marksToAttributes`: `[Mark]` → `{ markName: markAttrs }`.
    static func attributes(for marks: [Mark]) -> [String: [String: JSONValue]] {
        var result: [String: [String: JSONValue]] = [:]
        for mark in marks where mark.type != reservedKey {
            result[mark.type] = mark.attrs
        }
        return result
    }

    /// `attributesToMarks`: `{ markKey: markAttrs }` → `[Mark]`, sorted by type for
    /// determinism. `ychange` and any key whose value is not a plain attrs object
    /// are skipped (opaque preservation is #70).
    static func marks(from attributes: [String: [String: JSONValue]]) -> [Mark] {
        attributes
            .compactMap { key, attrs -> Mark? in
                let name = markName(forKey: key)
                guard name != reservedKey else { return nil }
                return Mark(type: name, attrs: attrs)
            }
            .sorted { $0.type < $1.type }
    }

    /// `yattr2markname`: an overlapping-mark key is `name--XXXXXXXX` (8 base64
    /// chars). Strip that suffix to recover the mark name; a plain name is returned
    /// unchanged.
    static func markName(forKey key: String) -> String {
        guard let range = key.range(of: "--[A-Za-z0-9+/]{8}$", options: .regularExpression) else {
            return key
        }
        return String(key[..<range.lowerBound])
    }
}
