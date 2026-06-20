#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

public protocol Pasteboard: AnyObject {
    var hasStrings: Bool { get }
    var string: String? { get set }
}

#if canImport(UIKit)
extension UIPasteboard: Pasteboard {}
#endif

#if canImport(AppKit)
extension NSPasteboard: Pasteboard {
    public var hasStrings: Bool {
        string(forType: .string) != nil
    }

    public var string: String? {
        get {
            string(forType: .string)
        }
        set {
            clearContents()
            guard let newValue else { return }
            setString(newValue, forType: .string)
        }
    }
}
#endif
