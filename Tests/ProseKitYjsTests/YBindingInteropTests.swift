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

    // MARK: - Fixture harness

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
