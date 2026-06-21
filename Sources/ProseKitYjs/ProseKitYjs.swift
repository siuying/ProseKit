import ProseEditor
import SwiftYrs

/// The Yjs-backed collaboration module, isolated from the editor core.
public enum ProseKitYjs {
    public static func makeDocument() -> YDoc {
        YDoc()
    }
}
