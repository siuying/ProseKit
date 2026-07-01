import CoreGraphics
import Foundation
import ProseModel
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A remote collaborator's selection, rendered as Selection Layer chrome: an
/// editor-drawn caret, range highlight, and name label in the peer's color.
/// Remote carets are editor-drawn overlays on both platforms — the system
/// only knows the local caret.
public struct RemoteSelection: Equatable {
    /// The peer's stable identity (an awareness client ID).
    public var id: UInt64
    public var name: String
    public var color: PlatformColor
    public var selection: TextSelection

    public init(id: UInt64, name: String, color: PlatformColor, selection: TextSelection) {
        self.id = id
        self.name = name
        self.color = color
        self.selection = selection
    }
}

/// The drawable geometry for one remote selection, computed against the
/// current layout through the same geometry path as the local caret and
/// recomputed on every relayout. Positions clamp to the document: awareness
/// states lag edits, so a peer's selection can momentarily outrun the text.
struct RemoteSelectionChrome: Equatable {
    var name: String
    var color: PlatformColor
    var caretRect: CGRect
    var highlightRects: [CGRect]

    @MainActor
    static func chrome(for selections: [RemoteSelection], core: EditorCore) -> [RemoteSelectionChrome] {
        let end = core.document.endPosition
        return selections.map { remote in
            let clamped = TextSelection(
                anchor: min(max(remote.selection.anchor, 0), end),
                head: min(max(remote.selection.head, 0), end)
            )
            return RemoteSelectionChrome(
                name: remote.name,
                color: remote.color,
                caretRect: core.caretRect(for: clamped.head),
                highlightRects: clamped.isCollapsed ? [] : core.selectionRects(for: clamped)
            )
        }
    }

    /// Draws the range highlight, caret, and name label into the current
    /// graphics context. Both platform layers draw in top-left-origin space.
    @MainActor
    func draw() {
        if !highlightRects.isEmpty {
            color.withAlphaComponent(0.25).setFill()
            for rect in highlightRects {
                fill(rect)
            }
        }
        guard !caretRect.isEmpty else { return }
        color.setFill()
        fill(caretRect.insetBy(dx: -0.5, dy: 0))
        drawLabel()
    }

    @MainActor
    private func drawLabel() {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        #else
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        #endif
        let text = NSAttributedString(string: name, attributes: [
            .font: font,
            .foregroundColor: PlatformColor.white,
        ])
        let textSize = text.size()
        let padding = CGSize(width: 4, height: 1)
        var pill = CGRect(
            x: caretRect.minX,
            y: caretRect.minY - textSize.height - padding.height * 2,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        // A caret on the first line has no room above; hang the label below.
        if pill.minY < 0 {
            pill.origin.y = caretRect.maxY
        }
        color.setFill()
        #if canImport(UIKit)
        UIBezierPath(roundedRect: pill, cornerRadius: 3).fill()
        #else
        NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
        #endif
        text.draw(at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height))
    }

    private func fill(_ rect: CGRect) {
        #if canImport(UIKit)
        UIBezierPath(rect: rect).fill()
        #else
        rect.fill()
        #endif
    }
}
