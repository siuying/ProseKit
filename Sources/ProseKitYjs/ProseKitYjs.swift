import ProseEditor
import SwiftYrs

/// The Yjs-backed collaboration module (`ProseKitYjs`), modeled on
/// y-prosemirror and built on SwiftYrs. `ProseModel`/`ProseEditor` never import
/// SwiftYrs, so collaboration is strictly opt-in: only this target links it.
///
/// The Binding (a later slice) drives convergence through the `EditorCore`
/// collaboration seam — `EditorCore.didApplyTransaction` outbound and
/// `EditorCore.applyRemote(_:)` inbound — keeping the editor core Yjs-agnostic.
public enum ProseKitYjs {
    /// Confirms the target links SwiftYrs by touching its API.
    public static func makeDocument() -> YDoc {
        YDoc()
    }
}
