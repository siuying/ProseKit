import XCTest
@testable import ProseEditor
@testable import ProseModel

final class InputRuleTests: XCTestCase {
    private func state(_ text: String) -> EditorState {
        // Caret at the end of a single paragraph whose text is `text`.
        EditorState(
            document: Document(.doc([.paragraph([.text(text)])])),
            selection: TextSelection(anchor: 2 + text.count, head: 2 + text.count)
        )
    }

    func testHashSpaceBecomesHeadingLevelOne() throws {
        var s = state("# ")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "heading")
        XCTAssertEqual(s.document.root.content[0].attrs["level"], .int(1))
        XCTAssertEqual(s.document.root.content[0].plainText, "", "the trigger text is consumed")
    }

    func testMultipleHashesChooseLevel() throws {
        var s = state("### ")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].attrs["level"], .int(3))
    }

    func testDashSpaceBecomesBulletList() throws {
        var s = state("- ")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "bulletList")
        XCTAssertEqual(s.document.root.content[0].content.map(\.type), ["listItem"])
        XCTAssertEqual(s.document.root.content[0].content[0].content.map(\.type), ["paragraph"])
        XCTAssertEqual(s.document.root.content[0].plainText, "", "the trigger text is consumed")
        XCTAssertEqual(s.selection, TextSelection(anchor: 4, head: 4))
    }

    func testStarSpaceBecomesBulletList() throws {
        var s = state("* ")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "bulletList")
    }

    func testOneDotSpaceBecomesOrderedList() throws {
        var s = state("1. ")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "orderedList")
        XCTAssertEqual(s.document.root.content[0].attrs["start"], .int(1))
        XCTAssertEqual(s.document.root.content[0].content.map(\.type), ["listItem"])
        XCTAssertEqual(s.selection, TextSelection(anchor: 4, head: 4))
    }

    func testNonTriggerTextDoesNothing() throws {
        var s = state("#x ")
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "paragraph")
    }

    func testTriggerNotAtBlockStartDoesNotFire() throws {
        var s = state("a# ")
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].type, "paragraph")
    }

    // MARK: - Finder API (Phase 0)

    func testExactFinderMatchesWholeBlockText() {
        let rule = InputRule.exactBlock(trigger: "> ") { _, _, _ in }
        let match = rule.find("> ")
        XCTAssertEqual(match?.range, 0..<2)
        XCTAssertEqual(match?.text, "> ")
        XCTAssertNil(match?.contentRange)
    }

    func testExactFinderRejectsPartialAndTrailing() {
        let rule = InputRule.exactBlock(trigger: "> ") { _, _, _ in }
        XCTAssertNil(rule.find(">"))
        XCTAssertNil(rule.find(" > "))
        XCTAssertNil(rule.find("a> "))
        XCTAssertNil(rule.find("> x"))
    }

    // MARK: - Inline mark rules (Phase 2)

    /// The single text run of the (only) block, with its marks.
    private func firstRun(_ s: EditorState) -> Node? {
        s.document.root.content.first?.content.first
    }

    func testStarBecomesItalic() throws {
        var s = state("*Italic*")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Italic")
        XCTAssertEqual(firstRun(s)?.marks, [.italic])
    }

    func testUnderscoreBecomesItalic() throws {
        var s = state("_Italic_")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Italic")
        XCTAssertEqual(firstRun(s)?.marks, [.italic])
    }

    func testDoubleStarBecomesBold() throws {
        var s = state("**Bold**")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Bold")
        XCTAssertEqual(firstRun(s)?.marks, [.bold])
    }

    func testDoubleUnderscoreBecomesBold() throws {
        var s = state("__Bold__")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Bold")
        XCTAssertEqual(firstRun(s)?.marks, [.bold])
    }

    func testBacktickBecomesCode() throws {
        var s = state("`Code`")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Code")
        XCTAssertEqual(firstRun(s)?.marks, [.code])
    }

    func testTildeBecomesStrike() throws {
        var s = state("~~Strike~~")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "Strike")
        XCTAssertEqual(firstRun(s)?.marks, [.strike])
    }

    func testEmptyDelimiterPairsDoNotFire() throws {
        for text in ["**", "____", "``", "~~~~"] {
            var s = state(text)
            XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s), "\(text) should not fire")
            XCTAssertEqual(s.document.root.content[0].plainText, text)
        }
    }

    func testWhitespaceOnlyContentDoesNotFire() throws {
        var s = state("* *")
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "* *")
    }

    func testPrecedingCharBeforeCodeIsPreserved() throws {
        var s = state("a`Code`")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "aCode")
        let runs = s.document.root.content[0].content
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].text, "a")
        XCTAssertEqual(runs[0].marks, [])
        XCTAssertEqual(runs[1].text, "Code")
        XCTAssertEqual(runs[1].marks, [.code])
    }

    func testDoubleBacktickDoesNotFireCode() throws {
        // The opening backtick is preceded by a backtick: Tiptap's code rule
        // rejects this so ``x` stays literal.
        var s = state("``Code`")
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "``Code`")
    }

    func testOnlyFinalPairTransforms() throws {
        // `*a*b*`: only the trailing `*b*` becomes italic; the leading `*a` is
        // preserved literally.
        var s = state("*a*b*")
        XCTAssertTrue(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "*ab")
        let runs = s.document.root.content[0].content
        XCTAssertEqual(runs.last?.text, "b")
        XCTAssertEqual(runs.last?.marks, [.italic])
    }

    func testMalformedDoubleStarTailStaysLiteral() throws {
        // `**Bold*` (one trailing star) must not italicise from the second star.
        var s = state("**Bold*")
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "**Bold*")
    }

    func testInlineRuleIsANoopWhenBlockTextSpansMarkRuns() throws {
        // Phase 2 keeps inline matches inside a single text node. When the
        // block already carries a split mark run before the caret, the matcher
        // can't read across runs, so the rule is a graceful no-op (no crash,
        // document untouched) rather than a partial transform.
        var s = EditorState(
            document: Document(.doc([.paragraph([.text("x", marks: [.bold]), .text("*i*")])])),
            selection: TextSelection(anchor: 6, head: 6)
        )
        XCTAssertFalse(try InputRules.apply(InputRules.starterKit, to: &s))
        XCTAssertEqual(s.document.root.content[0].plainText, "x*i*")
    }
}
