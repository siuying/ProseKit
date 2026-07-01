import XCTest
import ProseEditor
import ProseModel
import SwiftYrs
@testable import ProseKitYjs

/// Property-based CRDT convergence guard for the Yjs binding.
///
/// Case-by-case tests (`YBindingTests`, the interop suite) prove specific
/// scenarios converge. This suite instead generates *randomised* concurrent
/// edit sequences, applies them to two independent `YBinding`s, syncs, and
/// asserts both peers land on byte-identical shared-replica state **and** an
/// identical rendered `Document`. That catches diff/merge bugs the fixtures
/// miss, broadly rather than one hand-written case at a time.
///
/// Every trial is driven by a seeded PRNG, and the seed is printed on any
/// failure, so a divergence is deterministically reproducible: pin `baseSeed`
/// (or call `runTrial(seed:)` with the logged seed) to replay the exact edits.
@MainActor
final class YBindingConvergencePropertyTests: XCTestCase {
    /// Number of independent randomised trials per run. Each is cheap (two
    /// in-process peers, a handful of edits), so a few dozen stays well within
    /// a CI time budget while covering a wide spread of interleavings.
    private let trialCount = 60

    /// Fixed base so the suite itself is reproducible run-to-run; each trial
    /// derives its own seed from this, and the per-trial seed is what gets
    /// logged on failure.
    private let baseSeed: UInt64 = 0x50FA_17ED_C0FF_EE00

    func testRandomConcurrentEditsConvergeToIdenticalDocuments() async throws {
        for trial in 0..<trialCount {
            let seed = baseSeed &+ UInt64(trial)
            try await runTrial(seed: seed)
        }
    }

    // MARK: - One trial

    private func runTrial(seed: UInt64) async throws {
        var rng = SplitMix64(seed: seed)

        // Two peers over a shared replica, joined the same way a provider would:
        // A seeds the first paragraph, B joins after syncing the non-empty state.
        let coreA = EditorCore(document: Document(.doc([.paragraph([.text("seed")])])))
        let docA = YDoc()
        let bindingA = YBinding(core: coreA, doc: docA)
        bindingA.join()

        let coreB = EditorCore(document: Document(.doc([.paragraph([])])))
        let docB = YDoc()
        try sync(docA, docB)
        let bindingB = YBinding(core: coreB, doc: docB)
        bindingB.join()

        XCTAssertEqual(
            coreB.document, coreA.document,
            "peers did not start from a common state (seed=\(hex(seed)))"
        )

        // Several rounds of concurrent edits: both peers edit locally with no
        // sync in between (the concurrency that exercises the CRDT), then a
        // single bidirectional sync delivers every update to both sides.
        let rounds = Int.random(in: 1...5, using: &rng)
        for _ in 0..<rounds {
            let editsA = Int.random(in: 0...4, using: &rng)
            for _ in 0..<editsA { try applyRandomEdit(to: coreA, using: &rng) }
            let editsB = Int.random(in: 0...4, using: &rng)
            for _ in 0..<editsB { try applyRandomEdit(to: coreB, using: &rng) }

            try sync(docA, docB)
            try await settle(coreA, docA, coreB, docB)
        }

        // Convergence: Yjs guarantees both replicas hold the same state once each
        // has the other's updates. The replica is the authority, so assert both
        // replicas agree AND each core actually rendered that merged state — not
        // merely that the two cores match each other (which two equally-stale
        // cores could satisfy without reflecting the merged replica).
        let replica = try replicaText(docA)
        XCTAssertEqual(
            try replicaText(docB), replica,
            "shared replica diverged (seed=\(hex(seed)))"
        )
        XCTAssertEqual(
            coreA.document.plainText, replica,
            "peer A did not render the merged replica (seed=\(hex(seed)))"
        )
        XCTAssertEqual(
            coreB.document.plainText, replica,
            "peer B did not render the merged replica (seed=\(hex(seed)))"
        )
        XCTAssertEqual(
            coreA.document, coreB.document,
            "rendered Documents diverged (seed=\(hex(seed)))"
        )
        withExtendedLifetime((bindingA, bindingB)) {}
    }

    // MARK: - Random edit

    /// Applies one random intra-paragraph edit — an insert or a delete — at a
    /// random position. Restricted to plain characters (no "\n"): this suite
    /// proves text-level CRDT convergence; block/mark convergence is covered by
    /// the interop matrix.
    private func applyRandomEdit(to core: EditorCore, using rng: inout SplitMix64) throws {
        let start = core.document.startTextPosition
        let end = core.document.endTextPosition

        // Bias toward inserts so the document grows rather than collapsing to
        // empty, keeping later edits meaningful.
        let shouldDelete = end > start && Int.random(in: 0...2, using: &rng) == 0
        if shouldDelete {
            let a = Int.random(in: start...end, using: &rng)
            let b = Int.random(in: start...end, using: &rng)
            let lower = min(a, b)
            var upper = max(a, b)
            // deleteBackward on a collapsed caret needs a character before it to
            // remove; extend a zero-width pick by one so the edit is a real op.
            if lower == upper { upper = min(upper + 1, end) }
            guard upper > lower else { return }
            core.setSelection(TextSelection(anchor: lower, head: upper))
            try core.deleteBackward()
        } else {
            let position = Int.random(in: start...end, using: &rng)
            core.setSelection(TextSelection(anchor: position, head: position))
            try core.insertText(randomText(using: &rng), applyingInputRules: false)
        }
    }

    private func randomText(using rng: inout SplitMix64) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz ")
        let count = Int.random(in: 1...3, using: &rng)
        return String((0..<count).map { _ in alphabet.randomElement(using: &rng)! })
    }

    // MARK: - Harness

    /// Exchanges full state both ways, exactly as a provider's sync would.
    private func sync(_ a: YDoc, _ b: YDoc) throws {
        try b.apply(a.encodeStateAsUpdateV1(from: b.stateVector()))
        try a.apply(b.encodeStateAsUpdateV1(from: a.stateVector()))
    }

    /// Lets the bindings' replica observers deliver remote updates into the
    /// cores before asserting. Waits until each core has rendered *its own
    /// replica* (the convergence authority) and the two replicas agree, so an
    /// equally-stale pair of cores cannot end the loop prematurely.
    private func settle(_ coreA: EditorCore, _ docA: YDoc, _ coreB: EditorCore, _ docB: YDoc) async throws {
        for _ in 0..<20 {
            let replicaA = try replicaText(docA)
            let replicaB = try replicaText(docB)
            if replicaA == replicaB,
               coreA.document.plainText == replicaA,
               coreB.document.plainText == replicaB {
                return
            }
            await Task.yield()
        }
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

    private func hex(_ seed: UInt64) -> String { "0x" + String(seed, radix: 16, uppercase: true) }
}

/// Deterministic, seedable PRNG (SplitMix64). Swift's system generator is not
/// seedable, so replays would be impossible; this makes every trial's edit
/// stream a pure function of its seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
