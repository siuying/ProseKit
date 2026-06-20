#if canImport(UIKit) || canImport(AppKit)
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Parses a Tiptap highlight `color` value into a platform colour for the Canvas, and
/// maps the known default-palette colours to dynamic colours so a highlight
/// stays legible in dark mode. Anything it cannot parse returns nil — the run
/// keeps its Mark but draws no background (ADR 0005). Arbitrary parseable
/// colours render literally; only the shipped palette gets a dark-mode variant.
enum HighlightColor {
    /// Light-mode hex (lowercased, `#`-prefixed) → its dark-mode replacement.
    static let darkModePalette: [String: PlatformColor] = [
        "#ffd54f": PlatformColor(red: 0.42, green: 0.36, blue: 0.10, alpha: 1),  // yellow
        "#ff8a80": PlatformColor(red: 0.44, green: 0.18, blue: 0.16, alpha: 1),  // red
        "#80d8ff": PlatformColor(red: 0.13, green: 0.30, blue: 0.40, alpha: 1),  // blue
        "#ccff90": PlatformColor(red: 0.22, green: 0.36, blue: 0.13, alpha: 1),  // green
        "#ea80fc": PlatformColor(red: 0.36, green: 0.16, blue: 0.42, alpha: 1),  // purple
    ]

    static func color(for value: String) -> PlatformColor? {
        guard let light = parseHex(value) else { return nil }
        guard let dark = darkModePalette[value.lowercased()] else { return light }
        #if canImport(UIKit)
        return PlatformColor { $0.userInterfaceStyle == .dark ? dark : light }
        #else
        return PlatformColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        #endif
    }

    static func parseHex(_ value: String) -> PlatformColor? {
        var hex = value.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let int = UInt32(hex, radix: 16) else { return nil }
        return PlatformColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
