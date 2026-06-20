import CoreGraphics

#if canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor

extension PlatformColor {
    static var canvasBackground: PlatformColor { .systemBackground }
}
#elseif canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor

extension PlatformColor {
    static var label: PlatformColor { .labelColor }
    static var canvasBackground: PlatformColor { .textBackgroundColor }
    static var tertiaryLabel: PlatformColor { .tertiaryLabelColor }
    static var systemGray3: PlatformColor { .systemGray }
    static var systemGreen: PlatformColor { NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1) }
    static var systemTeal: PlatformColor { NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.90, alpha: 1) }

    var proseCGColor: CGColor {
        usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.labelColor.cgColor
    }
}
#endif
