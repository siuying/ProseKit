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
