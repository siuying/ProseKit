// The interop harness spawns a Node subprocess (`Foundation.Process`), which is
// only available on macOS. Gating the whole suite keeps the iOS-simulator test
// target compiling (Process is unavailable there and the simulator sandbox
// cannot launch external processes anyway).
#if os(macOS)
import XCTest
import Foundation
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

/// Cross-implementation convergence proof for the slice-1 tracer bullet.
///
/// Every other `YBinding` test converges two `SwiftYrs` peers. This suite instead
/// converges the Swift `YBinding` with the **real** `y-prosemirror` library — the
/// same binding Tiptap drives in the browser — run headless in Node. The two
/// peers exchange nothing but standard Yjs v1 update bytes, so identical text on
/// both sides is genuine ProseKit ⇄ browser-peer convergence, not a Swift-only
/// round-trip.
///
/// The fixture (`Tests/Interop`) needs Node and its `npm install`. When either is
/// absent (e.g. a network-restricted CI) the tests `XCTSkip` rather than fail.
@MainActor
final class YBindingInteropTests: XCTestCase {
    /// The two peers only converge if they key the shared type on the *same* root
    /// XML-fragment field name. A rename on either side would otherwise silently
    /// produce two disjoint documents that never converge, so assert equality
    /// explicitly and fail loudly on drift.
    func testFragmentFieldNameMatchesTheRealYProsemirrorPeer() throws {
        let fixture = try requireFixture()
        let jsFragment = try fixture.run("fragment")
        XCTAssertEqual(jsFragment, YBinding.defaultFragmentName)
    }

    func testProseKitDecodesUpdateFromRealYProsemirrorPeer() throws {
        let fixture = try requireFixture()
        let text = "Hello from y-prosemirror"

        let updateFile = makeTempFile()
        try fixture.run("encode", text, updateFile.path)
        let update = try Data(contentsOf: updateFile)

        let doc = YDoc()
        try doc.apply(.v1(update))

        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        XCTAssertEqual(core.document.plainText, text)
    }

    func testRealYProsemirrorDecodesProseKitEdit() throws {
        let fixture = try requireFixture()
        let text = "Edited in ProseKit"

        let core = EditorCore(document: Document(.doc([.paragraph([.text(text)])])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join() // empty replica + non-empty document → encodes the text into Y

        let update = try doc.encodeStateAsUpdateV1()
        let updateFile = makeTempFile()
        try update.data.write(to: updateFile)

        let decoded = try fixture.run("decode", updateFile.path)
        XCTAssertEqual(decoded, text)
    }

    func testRemoteYProsemirrorEditConvergesAfterJoin() throws {
        let fixture = try requireFixture()

        // ProseKit joins first with its own text; the y-prosemirror peer then
        // produces a different paragraph and the two updates are merged, exactly
        // as a provider's sync would. Both sides must converge to the same text.
        let core = EditorCore(document: Document(.doc([.paragraph([.text("from prosekit")])])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let remoteFile = makeTempFile()
        try fixture.run("encode", "from prosekit and browser", remoteFile.path)
        try doc.apply(.v1(Data(contentsOf: remoteFile)))

        let merged = try doc.encodeStateAsUpdateV1()
        let mergedFile = makeTempFile()
        try merged.data.write(to: mergedFile)
        let jsText = try fixture.run("decode", mergedFile.path)

        // The Swift peer and the JS peer read identical text out of the shared replica.
        XCTAssertEqual(jsText, try replicaText(doc))
    }

    // MARK: - Marks

    func testRealYProsemirrorDecodesProseKitMarks() throws {
        let fixture = try requireFixture()
        let link = Mark.link(href: "https://example.com")
        let core = EditorCore(document: Document(.doc([.paragraph([
            .text("bold", marks: [.bold]),
            .text(" plain"),
            .text(" link", marks: [link]),
        ])])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let update = try doc.encodeStateAsUpdateV1()
        let file = makeTempFile()
        try update.data.write(to: file)

        let marks = Self.marksByText(try fixture.run("decodeJSON", file.path))
        XCTAssertEqual(marks["bold"], ["bold"])
        XCTAssertEqual(marks[" plain"], [])
        XCTAssertEqual(marks[" link"], ["link:https://example.com"])
        withExtendedLifetime(binding) {}
    }

    func testProseKitDecodesMarksFromRealYProsemirror() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[{"type":"paragraph","content":[
        {"type":"text","text":"bold","marks":[{"type":"bold"}]},
        {"type":"text","text":" link","marks":[{"type":"link","attrs":{"href":"https://example.com"}}]}
        ]}]}
        """#
        let jsonFile = makeTempFile()
        try Data(json.utf8).write(to: jsonFile)
        let outFile = makeTempFile()
        try fixture.run("encodeJSON", jsonFile.path, outFile.path)

        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: outFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let block = try XCTUnwrap(core.document.root.content.first)
        let runs = MarkedText(textblock: block).runs
        XCTAssertEqual(runs.map(\.text), ["bold", " link"])
        XCTAssertEqual(runs.first?.marks, [.bold])
        XCTAssertEqual(runs.last?.marks, [.link(href: "https://example.com")])
        withExtendedLifetime(binding) {}
    }

    /// Maps each decoded text run to a sorted list of mark descriptors
    /// (`"bold"`, `"link:<href>"`), for asserting what the JS peer sees.
    private static func marksByText(_ json: String) -> [String: [String]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paragraph = (root["content"] as? [[String: Any]])?.first,
              let inline = paragraph["content"] as? [[String: Any]] else { return [:] }
        var result: [String: [String]] = [:]
        for node in inline {
            guard let text = node["text"] as? String else { continue }
            let marks = (node["marks"] as? [[String: Any]] ?? []).map { mark -> String in
                let type = mark["type"] as? String ?? "?"
                if let href = (mark["attrs"] as? [String: Any])?["href"] as? String {
                    return "\(type):\(href)"
                }
                return type
            }
            result[text] = marks.sorted()
        }
        return result
    }

    // MARK: - Block types and attrs

    func testRealYProsemirrorDecodesProseKitBlocks() throws {
        let fixture = try requireFixture()
        let core = EditorCore(document: Document(.doc([
            .heading(level: 2, [.text("Title")]),
            .paragraph([.text("body")]),
        ])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let update = try doc.encodeStateAsUpdateV1()
        let file = makeTempFile()
        try update.data.write(to: file)

        let blocks = Self.blocksFromJSON(try fixture.run("decodeJSON", file.path))
        XCTAssertEqual(blocks.map(\.type), ["heading", "paragraph"])
        XCTAssertEqual(blocks.first?.level, 2)
        XCTAssertEqual(blocks.first?.text, "Title")
        withExtendedLifetime(binding) {}
    }

    func testProseKitDecodesBlocksFromRealYProsemirror() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[
        {"type":"heading","attrs":{"level":3},"content":[{"type":"text","text":"Title"}]},
        {"type":"paragraph","content":[{"type":"text","text":"body"}]}
        ]}
        """#
        let jsonFile = makeTempFile()
        try Data(json.utf8).write(to: jsonFile)
        let outFile = makeTempFile()
        try fixture.run("encodeJSON", jsonFile.path, outFile.path)

        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: outFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        XCTAssertEqual(core.document.root.content.map(\.type), ["heading", "paragraph"])
        XCTAssertEqual(core.document.root.content[0].attrs["level"], .int(3))
        XCTAssertEqual(core.document.plainText, "Titlebody")
        withExtendedLifetime(binding) {}
    }

    private static func blocksFromJSON(_ json: String) -> [(type: String, level: Int?, text: String)] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else { return [] }
        return content.map { block in
            let type = block["type"] as? String ?? "?"
            let level = (block["attrs"] as? [String: Any])?["level"] as? Int
            let text = (block["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
            return (type: type, level: level, text: text)
        }
    }

    // MARK: - Nesting / lists

    func testRealYProsemirrorDecodesProseKitNestedList() throws {
        let fixture = try requireFixture()
        let core = EditorCore(document: Document(.doc([
            .bulletList([
                .listItem([.paragraph([.text("one")])]),
                .listItem([.paragraph([.text("two")])]),
            ]),
        ])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let update = try doc.encodeStateAsUpdateV1()
        let file = makeTempFile()
        try update.data.write(to: file)

        let json = try fixture.run("decodeJSON", file.path)
        // Compare against the JS peer's own JSON for the same document.
        XCTAssertTrue(json.contains("\"bulletList\""))
        XCTAssertTrue(json.contains("\"listItem\""))
        XCTAssertTrue(json.contains("\"one\"") && json.contains("\"two\""))
        withExtendedLifetime(binding) {}
    }

    func testProseKitDecodesNestedListFromRealYProsemirror() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[{"type":"bulletList","content":[
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"one"}]}]},
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"two"}]}]}
        ]}]}
        """#
        let jsonFile = makeTempFile()
        try Data(json.utf8).write(to: jsonFile)
        let outFile = makeTempFile()
        try fixture.run("encodeJSON", jsonFile.path, outFile.path)

        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: outFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        XCTAssertEqual(core.document.root.content, [
            .bulletList([
                .listItem([.paragraph([.text("one")])]),
                .listItem([.paragraph([.text("two")])]),
            ]),
        ])
        withExtendedLifetime(binding) {}
    }

    // MARK: - Opaque round-trip (#70, convergence-critical)

    func testUnknownNodeSurvivesProseKitEditAndSync() throws {
        let fixture = try requireFixture()
        // The JS peer authors a node ProseKit's Schema does not know (an `image`
        // atom) between two paragraphs.
        let json = #"""
        {"type":"doc","content":[
        {"type":"paragraph","content":[{"type":"text","text":"a"}]},
        {"type":"image","attrs":{"src":"cat.png"}},
        {"type":"paragraph","content":[{"type":"text","text":"b"}]}
        ]}
        """#
        let jsonFile = makeTempFile()
        try Data(json.utf8).write(to: jsonFile)
        let updateFile = makeTempFile()
        try fixture.run("encodeJSON", jsonFile.path, updateFile.path)

        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: updateFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        XCTAssertEqual(core.document.root.content.map(\.type), ["paragraph", "image", "paragraph"])

        // ProseKit edits a neighbouring paragraph — the unknown node must survive.
        let end = (core.document.position(ofNodeAtPath: [0]) ?? 0) + 1 + 1
        core.setSelection(TextSelection(anchor: end, head: end))
        try core.insertText("Z")

        let mergedFile = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: mergedFile)
        let decoded = try fixture.run("decodeJSON", mergedFile.path)

        // The JS peer still sees the image (with its src) and ProseKit's edit.
        XCTAssertTrue(decoded.contains("\"image\""), decoded)
        XCTAssertTrue(decoded.contains("\"cat.png\""), decoded)
        XCTAssertTrue(decoded.contains("\"aZ\""), decoded)
        XCTAssertTrue(decoded.contains("\"b\""), decoded)
        withExtendedLifetime(binding) {}
    }

    // MARK: - Marks matrix (full wire-format contract, both directions)

    /// Every mark ProseKit's Schema authors, in one paragraph, decoded by the real
    /// JS peer — proves the whole `marksToAttributes` contract (plain names + attr
    /// marks), not just bold/link.
    func testMarksMatrixRealYProsemirrorDecodesProseKit() throws {
        let fixture = try requireFixture()
        let core = EditorCore(document: Document(.doc([.paragraph([
            .text("b", marks: [.bold]),
            .text("i", marks: [.italic]),
            .text("s", marks: [.strike]),
            .text("c", marks: [.code]),
            .text("u", marks: [.underline]),
            .text("p", marks: [.superscript]),
            .text("q", marks: [.`subscript`]),
            .text("h", marks: [.highlight(color: "yellow")]),
            .text("l", marks: [.link(href: "https://example.com")]),
        ])])))
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()

        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)

        let marks = Self.allMarksByText(try fixture.run("decodeJSON", file.path))
        XCTAssertEqual(marks["b"], ["bold"])
        XCTAssertEqual(marks["i"], ["italic"])
        XCTAssertEqual(marks["s"], ["strike"])
        XCTAssertEqual(marks["c"], ["code"])
        XCTAssertEqual(marks["u"], ["underline"])
        XCTAssertEqual(marks["p"], ["superscript"])
        XCTAssertEqual(marks["q"], ["subscript"])
        XCTAssertEqual(marks["h"], ["highlight(color=yellow)"])
        XCTAssertEqual(marks["l"], ["link(href=https://example.com)"])
        withExtendedLifetime(binding) {}
    }

    /// The same matrix authored by the JS peer and decoded by ProseKit — every
    /// mark key round-trips to the exact ProseKit `Mark` value.
    func testProseKitDecodesMarksMatrixFromRealYProsemirror() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[{"type":"paragraph","content":[
        {"type":"text","text":"b","marks":[{"type":"bold"}]},
        {"type":"text","text":"i","marks":[{"type":"italic"}]},
        {"type":"text","text":"s","marks":[{"type":"strike"}]},
        {"type":"text","text":"c","marks":[{"type":"code"}]},
        {"type":"text","text":"u","marks":[{"type":"underline"}]},
        {"type":"text","text":"p","marks":[{"type":"superscript"}]},
        {"type":"text","text":"q","marks":[{"type":"subscript"}]},
        {"type":"text","text":"h","marks":[{"type":"highlight","attrs":{"color":"yellow"}}]},
        {"type":"text","text":"l","marks":[{"type":"link","attrs":{"href":"https://example.com"}}]}
        ]}]}
        """#
        let core = try decodeIntoProseKit(json, using: fixture).core

        let block = try XCTUnwrap(core.document.root.content.first)
        let runs = MarkedText(textblock: block).runs
        XCTAssertEqual(runs.map(\.text), ["b", "i", "s", "c", "u", "p", "q", "h", "l"])
        XCTAssertEqual(runs.map { $0.marks.map(\.type) }, [
            ["bold"], ["italic"], ["strike"], ["code"], ["underline"],
            ["superscript"], ["subscript"], ["highlight"], ["link"],
        ])
        XCTAssertEqual(runs[7].marks, [.highlight(color: "yellow")])
        XCTAssertEqual(runs[8].marks, [.link(href: "https://example.com")])
    }

    // MARK: - Block types & attrs (blockquote, textAlign, opaque codeBlock)

    func testBlockquoteConvergesBothDirections() throws {
        let fixture = try requireFixture()
        let document = Document(.doc([
            .blockquote([.paragraph([.text("quoted")])]),
            .paragraph([.text("after")]),
        ]))

        // ProseKit -> JS
        let core = EditorCore(document: document)
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)
        let json = try fixture.run("decodeJSON", file.path)
        XCTAssertTrue(json.contains("\"blockquote\""), json)
        XCTAssertTrue(json.contains("\"quoted\""), json)

        // JS -> ProseKit
        let roundTrip = try decodeIntoProseKit(json, using: fixture).core
        XCTAssertEqual(roundTrip.document.root.content, document.root.content)
        withExtendedLifetime(binding) {}
    }

    func testTextAlignAttrConvergesBothDirections() throws {
        let fixture = try requireFixture()
        let document = Document(.doc([
            Node(type: "paragraph", attrs: ["textAlign": .string("center")], content: [.text("centered")]),
            Node(type: "heading", attrs: ["level": .int(2), "textAlign": .string("right")], content: [.text("titled")]),
        ]))

        // ProseKit -> JS: the JS peer reads the same alignment attrs off the elements.
        let core = EditorCore(document: document)
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)
        let json = try fixture.run("decodeJSON", file.path)
        XCTAssertTrue(json.contains("\"textAlign\":\"center\""), json)
        XCTAssertTrue(json.contains("\"textAlign\":\"right\""), json)

        // JS -> ProseKit: alignment attrs survive back to identical ProseKit Nodes.
        let roundTrip = try decodeIntoProseKit(json, using: fixture).core
        XCTAssertEqual(roundTrip.document.root.content, document.root.content)
        withExtendedLifetime(binding) {}
    }

    /// `codeBlock` is not in ProseKit's Schema, so it converges via the opaque
    /// path (#70): a JS-authored code block survives a ProseKit edit-and-sync
    /// cycle byte-faithfully and the JS peer still reads its text back.
    func testOpaqueCodeBlockSurvivesProseKitEditAndSync() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[
        {"type":"paragraph","content":[{"type":"text","text":"a"}]},
        {"type":"codeBlock","content":[{"type":"text","text":"let x = 1"}]}
        ]}
        """#
        let peer = try decodeIntoProseKit(json, using: fixture)
        let core = peer.core
        XCTAssertEqual(core.document.root.content.map(\.type), ["paragraph", "codeBlock"])

        // Edit the neighbouring paragraph; the opaque code block must survive.
        let start = (core.document.position(ofNodeAtPath: [0]) ?? 0) + 1
        core.setSelection(TextSelection(anchor: start, head: start))
        try core.insertText("Z")

        let merged = makeTempFile()
        try peer.doc.encodeStateAsUpdateV1().data.write(to: merged)
        let decoded = try fixture.run("decodeJSON", merged.path)
        XCTAssertTrue(decoded.contains("\"codeBlock\""), decoded)
        XCTAssertTrue(decoded.contains("let x = 1"), decoded)
        XCTAssertTrue(decoded.contains("\"Za\""), decoded)
    }

    // MARK: - Nesting & lists (ordered start, task checked, nesting, reorder)

    func testOrderedListStartAttrConvergesBothDirections() throws {
        let fixture = try requireFixture()
        let document = Document(.doc([
            .orderedList(start: 3, [
                .listItem([.paragraph([.text("three")])]),
                .listItem([.paragraph([.text("four")])]),
            ]),
        ]))

        let core = EditorCore(document: document)
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)
        let json = try fixture.run("decodeJSON", file.path)
        XCTAssertTrue(json.contains("\"orderedList\""), json)
        XCTAssertTrue(json.contains("\"start\":3"), json)

        let roundTrip = try decodeIntoProseKit(json, using: fixture).core
        XCTAssertEqual(roundTrip.document.root.content, document.root.content)
        withExtendedLifetime(binding) {}
    }

    func testTaskListCheckedConvergesBothDirections() throws {
        let fixture = try requireFixture()
        let document = Document(.doc([
            .taskList([
                .taskItem(checked: true, [.paragraph([.text("done")])]),
                .taskItem(checked: false, [.paragraph([.text("todo")])]),
            ]),
        ]))

        let core = EditorCore(document: document)
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)
        let json = try fixture.run("decodeJSON", file.path)
        XCTAssertTrue(json.contains("\"taskList\""), json)
        XCTAssertTrue(json.contains("\"checked\":true"), json)

        let roundTrip = try decodeIntoProseKit(json, using: fixture).core
        XCTAssertEqual(roundTrip.document.root.content, document.root.content)
        withExtendedLifetime(binding) {}
    }

    func testNestedListConvergesBothDirections() throws {
        let fixture = try requireFixture()
        let document = Document(.doc([
            .bulletList([
                .listItem([
                    .paragraph([.text("parent")]),
                    .bulletList([
                        .listItem([.paragraph([.text("child")])]),
                    ]),
                ]),
            ]),
        ]))

        let core = EditorCore(document: document)
        let doc = YDoc()
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let file = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: file)
        let json = try fixture.run("decodeJSON", file.path)
        XCTAssertTrue(json.contains("\"parent\"") && json.contains("\"child\""), json)

        let roundTrip = try decodeIntoProseKit(json, using: fixture).core
        XCTAssertEqual(roundTrip.document.root.content, document.root.content)
        withExtendedLifetime(binding) {}
    }

    /// Concurrent edits into *untouched siblings* converge across the wire: the
    /// JS peer edits one list item's text while ProseKit concurrently edits a
    /// different item, and the merge keeps both — the acceptance case for Phase 4
    /// ("reordering and nesting changes preserve concurrent edits into untouched
    /// siblings"). The JS peer reconciles in place via the real `updateYFragment`,
    /// so its edit lands as minimal CRDT ops that merge with ProseKit's.
    func testConcurrentEditsIntoUntouchedSiblingsConverge() async throws {
        let fixture = try requireFixture()

        // Shared base: [a, b, c]. Both peers start from these bytes.
        let baseJSON = #"""
        {"type":"doc","content":[{"type":"bulletList","content":[
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]},
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"b"}]}]},
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"c"}]}]}
        ]}]}
        """#
        let baseJSONFile = makeTempFile()
        try Data(baseJSON.utf8).write(to: baseJSONFile)
        let baseFile = makeTempFile()
        try fixture.run("encodeJSON", baseJSONFile.path, baseFile.path)

        // ProseKit joins the shared replica and appends "Z" to the first item.
        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: baseFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        let afterA = (core.document.position(ofNodeAtPath: [0, 0, 0]) ?? 0) + 2 // after "a"
        core.setSelection(TextSelection(anchor: afterA, head: afterA))
        try core.insertText("Z")

        // JS peer, from the same base, appends "Q" to the *third* item (a sibling
        // ProseKit never touched).
        let jsEditJSON = #"""
        {"type":"doc","content":[{"type":"bulletList","content":[
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]},
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"b"}]}]},
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"cQ"}]}]}
        ]}]}
        """#
        let jsEditJSONFile = makeTempFile()
        try Data(jsEditJSON.utf8).write(to: jsEditJSONFile)
        let jsUpdate = makeTempFile()
        try fixture.run("mutateJSON", baseFile.path, jsEditJSONFile.path, jsUpdate.path)

        // Merge the JS peer's edit into ProseKit's replica. The fragment observer
        // reconciles the merged replica back into `core` asynchronously, so yield
        // until ProseKit has rendered it (as a provider's runloop would).
        try doc.apply(.v1(Data(contentsOf: jsUpdate)))
        let expected = ["aZ", "b", "cQ"]
        for _ in 0..<50 where core.document.root.content.first?.content.map(\.plainText) != expected {
            await Task.yield()
        }

        // Both peers converge to [aZ, b, cQ]: each peer's edit into its untouched
        // sibling survived the merge.
        let list = try XCTUnwrap(core.document.root.content.first)
        XCTAssertEqual(list.content.map(\.plainText), expected)

        let mergedFile = makeTempFile()
        try doc.encodeStateAsUpdateV1().data.write(to: mergedFile)
        let jsView = try fixture.run("decodeJSON", mergedFile.path)
        for text in expected {
            XCTAssertTrue(jsView.contains("\"\(text)\""), jsView)
        }
        withExtendedLifetime(binding) {}
    }

    // MARK: - Opaque round-trip: mark keys (#70)

    /// A mark key only the JS peer understands (`comment`) survives a full
    /// ProseKit edit-and-sync cycle: ProseKit carries it opaquely on the text run
    /// and re-emits it, so the JS peer still reads the comment with its id.
    func testUnknownMarkSurvivesProseKitEditAndSync() throws {
        let fixture = try requireFixture()
        let json = #"""
        {"type":"doc","content":[{"type":"paragraph","content":[
        {"type":"text","text":"flagged","marks":[{"type":"comment","attrs":{"id":"c1"}}]},
        {"type":"text","text":" tail"}
        ]}]}
        """#
        let peer = try decodeIntoProseKit(json, using: fixture)
        let core = peer.core

        // The comment mark is carried opaquely as a Mark whose type is the raw key.
        let block = try XCTUnwrap(core.document.root.content.first)
        let runs = MarkedText(textblock: block).runs
        XCTAssertEqual(runs.first?.marks, [Mark(type: "comment", attrs: ["id": .string("c1")])])

        // Edit the trailing (unmarked) run; the comment must survive re-encoding.
        let end = (core.document.position(ofNodeAtPath: [0]) ?? 0) + 1 + core.document.plainText.count
        core.setSelection(TextSelection(anchor: end, head: end))
        try core.insertText("!")

        let merged = makeTempFile()
        try peer.doc.encodeStateAsUpdateV1().data.write(to: merged)
        let decoded = try fixture.run("decodeJSON", merged.path)
        XCTAssertTrue(decoded.contains("\"comment\""), decoded)
        XCTAssertTrue(decoded.contains("\"c1\""), decoded)
        XCTAssertTrue(decoded.contains("tail!"), decoded)
    }

    /// Maps each decoded text run to a sorted list of full mark descriptors —
    /// `"bold"`, `"highlight(color=yellow)"`, `"link(href=…)"` — for asserting
    /// the whole marks matrix (types *and* attrs) the JS peer sees.
    private static func allMarksByText(_ json: String) -> [String: [String]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paragraph = (root["content"] as? [[String: Any]])?.first,
              let inline = paragraph["content"] as? [[String: Any]] else { return [:] }
        var result: [String: [String]] = [:]
        for node in inline {
            guard let text = node["text"] as? String else { continue }
            let marks = (node["marks"] as? [[String: Any]] ?? []).map { mark -> String in
                let type = mark["type"] as? String ?? "?"
                let attrs = (mark["attrs"] as? [String: Any]) ?? [:]
                guard !attrs.isEmpty else { return type }
                let pairs = attrs.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
                return "\(type)(\(pairs))"
            }
            result[text] = marks.sorted()
        }
        return result
    }

    // MARK: - Fixture harness

    /// A ProseKit replica joined to a Y.Doc: the `binding` must stay retained for
    /// local edits to keep propagating into `doc`, so callers hold the whole Peer.
    private struct Peer {
        let core: EditorCore
        let doc: YDoc
        let binding: YBinding
    }

    /// Encodes a full ProseMirror doc JSON with the real y-prosemirror peer, then
    /// applies the resulting Yjs v1 update into a fresh ProseKit replica — the
    /// canonical JS → ProseKit decode path shared by the matrix tests.
    private func decodeIntoProseKit(_ json: String, using fixture: Fixture) throws -> Peer {
        let jsonFile = makeTempFile()
        try Data(json.utf8).write(to: jsonFile)
        let updateFile = makeTempFile()
        try fixture.run("encodeJSON", jsonFile.path, updateFile.path)

        let doc = YDoc()
        try doc.apply(.v1(Data(contentsOf: updateFile)))
        let core = EditorCore(document: Document(.doc([.paragraph([])])))
        let binding = YBinding(core: core, doc: doc)
        binding.join()
        return Peer(core: core, doc: doc, binding: binding)
    }

    private func replicaText(_ doc: YDoc) throws -> String {
        let fragment = try doc.xmlFragment(named: YBinding.defaultFragmentName)
        return try doc.read { transaction -> String in
            guard try transaction.childCount(of: fragment) > 0,
                  case let .element(paragraph) = try transaction.child(at: 0, in: fragment),
                  try transaction.childCount(of: paragraph) > 0,
                  case let .text(textNode) = try transaction.child(at: 0, in: paragraph)
            else { return "" }
            return try transaction.string(from: textNode)
        }
    }

    private struct Fixture {
        let nodePath: String
        let scriptPath: String
        let workingDirectory: URL

        @discardableResult
        func run(_ arguments: String...) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [scriptPath] + arguments
            process.currentDirectoryURL = workingDirectory
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let errorText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "interop", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "node interop.mjs \(arguments.first ?? "") failed: \(errorText)",
                ])
            }
            return String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        }
    }

    private func requireFixture() throws -> Fixture {
        guard let nodePath = locateNode() else {
            throw XCTSkip("node not found on PATH; skipping y-prosemirror interop")
        }
        let interopDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProseKitYjsTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Interop")
        let modules = interopDir.appendingPathComponent("node_modules/y-prosemirror")
        guard FileManager.default.fileExists(atPath: modules.path) else {
            throw XCTSkip("Tests/Interop dependencies not installed (run `npm install` there); skipping interop")
        }
        return Fixture(
            nodePath: nodePath,
            scriptPath: interopDir.appendingPathComponent("interop.mjs").path,
            workingDirectory: interopDir
        )
    }

    /// Resolves `node` through a login shell so version managers (mise/nvm) on the
    /// user's PATH are honoured even when the test process inherits a bare env.
    private func locateNode() -> String? {
        if let direct = ProcessInfo.processInfo.environment["NODE_BINARY"],
           FileManager.default.isExecutableFile(atPath: direct) {
            return direct
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v node"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = Pipe()
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let path = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private func makeTempFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prosekit-interop-\(UUID().uuidString).bin")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
#endif
