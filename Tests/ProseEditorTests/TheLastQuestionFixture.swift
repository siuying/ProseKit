import Foundation

/// Fixture text for performance tests: "The Last Question" by Isaac Asimov
/// (1956), as published at http://www.thelastquestion.net/, loaded from
/// Resources/last_question.txt — the full story, one paragraph per
/// blank-line-separated block.
///
/// `onePage` is roughly one phone screen of paragraphs; `manyPages` repeats the
/// full story so the document spans dozens of screens.
enum TheLastQuestion {
    /// The full story, one element per paragraph (~180 paragraphs, ~25K characters).
    static let paragraphs: [String] = {
        guard let url = Bundle.module.url(forResource: "last_question", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("missing last_question.txt test resource")
        }
        return text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }()

    /// About one phone screen of text.
    static var onePage: [String] {
        Array(paragraphs.prefix(8))
    }

    /// The full story repeated five times (~900 paragraphs, ~125K characters),
    /// spanning many screens.
    static var manyPages: [String] {
        Array(repeating: paragraphs, count: 5).flatMap { $0 }
    }
}
