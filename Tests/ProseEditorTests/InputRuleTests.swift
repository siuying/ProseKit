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
}
