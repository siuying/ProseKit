import Foundation

/// Recognises when a pasted string is a single URL, so pasting it onto a
/// selection links the selection rather than replacing it (Q6). Autolink while
/// typing is deferred.
enum LinkDetection {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The URL string if `text` is exactly one link and nothing else, else nil.
    static func soleURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace), let detector else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector.matches(in: trimmed, range: range)
        guard matches.count == 1, let match = matches.first,
              match.range == range, let url = match.url else { return nil }
        return url.absoluteString
    }
}
