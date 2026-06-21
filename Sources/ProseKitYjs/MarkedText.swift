import Foundation
import ProseModel

/// One inline text run: a maximal string of characters sharing the same Marks.
struct MarkedRun: Equatable {
    var text: String
    var marks: [Mark]
}

/// The inline content of a single textblock, modelled both as ProseKit runs and
/// as a y-prosemirror `YXmlText` delta. This is the bridge the marks slice (#67)
/// converges across: a run of mixed-mark text is one `YXmlText` whose delta ops
/// each carry `marksToAttributes(run.marks)`.
struct MarkedText: Equatable {
    var runs: [MarkedRun]

    init(runs: [MarkedRun]) {
        self.runs = runs.filter { !$0.text.isEmpty }
    }

    /// Reads the inline runs of a textblock (e.g. the single paragraph of the
    /// marks slice). Non-text children are ignored (block nesting is #69).
    init(textblock: Node) {
        self.init(runs: textblock.content.compactMap { node in
            guard node.isText, let text = node.text else { return nil }
            return MarkedRun(text: text, marks: node.marks)
        })
    }

    /// Parses a SwiftYrs `deltaJSON` payload (`[{ "insert": <string>,
    /// "attributes": { markKey: attrs } }]`). Tolerant: a non-string insert or a
    /// malformed attribute value is skipped rather than crashing (`ychange` /
    /// hashed keys a richer peer may send — opaque preservation is #70).
    init(deltaJSON data: Data) {
        let ops = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        self.init(runs: ops.compactMap { op in
            guard let text = op["insert"] as? String, !text.isEmpty else { return nil }
            let attributes = op["attributes"] as? [String: Any] ?? [:]
            return MarkedRun(text: text, marks: MarkedText.marks(fromAttributes: attributes))
        })
    }

    /// Serialises to a SwiftYrs `deltaJSON` payload of insert ops carrying mark
    /// attributes, ready for `applyDeltaJSON`.
    func deltaJSON() throws -> Data {
        let ops: [[String: Any]] = runs.map { run in
            ["insert": run.text, "attributes": MarkedText.attributesObject(for: run.marks)]
        }
        return try JSONSerialization.data(withJSONObject: ops)
    }

    var plainText: String {
        runs.map(\.text).joined()
    }

    var characterCount: Int {
        runs.reduce(0) { $0 + $1.text.count }
    }

    /// The Marks at each character position, expanded from the runs.
    var marksPerCharacter: [[Mark]] {
        var result: [[Mark]] = []
        result.reserveCapacity(characterCount)
        for run in runs {
            for _ in 0..<run.text.count {
                result.append(run.marks)
            }
        }
        return result
    }

    // MARK: - Mark ⇄ JSON attribute object

    /// `{ markName: attrsObject }` as Foundation JSON objects, for `deltaJSON` /
    /// `format`. An empty mark attrs set becomes `{}` (y-prosemirror's shape).
    static func attributesObject(for marks: [Mark]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, attrs) in MarkAttributes.attributes(for: marks) {
            result[key] = jsonObject(from: attrs)
        }
        return result
    }

    static func marks(fromAttributes attributes: [String: Any]) -> [Mark] {
        var typed: [String: [String: JSONValue]] = [:]
        for (key, value) in attributes {
            guard let object = value as? [String: Any] else { continue }
            typed[key] = jsonAttrs(from: object)
        }
        return MarkAttributes.marks(from: typed)
    }

    /// A mark's `[String: JSONValue]` attrs as a Foundation JSON object, for
    /// `format` / `deltaJSON` payloads.
    static func foundationObject(from attrs: [String: JSONValue]) -> [String: Any] {
        attrs.mapValues(foundationValue)
    }

    private static func jsonObject(from attrs: [String: JSONValue]) -> [String: Any] {
        foundationObject(from: attrs)
    }

    private static func jsonAttrs(from object: [String: Any]) -> [String: JSONValue] {
        object.compactMapValues(jsonValue)
    }

    private static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case let .string(string): return string
        case let .int(int): return int
        case let .double(double): return double
        case let .bool(bool): return bool
        case .null: return NSNull()
        }
    }

    private static func jsonValue(_ value: Any) -> JSONValue? {
        switch value {
        case is NSNull:
            return JSONValue.null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .double(number.doubleValue)
            }
            return .int(number.intValue)
        default:
            return nil
        }
    }
}
