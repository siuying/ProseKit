#if canImport(UIKit)
import UIKit

/// The editor-owned overlay that draws remote collaborators' selection chrome
/// on iOS. The system (UITextInteraction) draws only the local caret, so
/// remote carets need their own layer, above the Canvas and below the system
/// chrome. Lives in content space: it scrolls with the text it annotates.
@MainActor final class RemoteSelectionLayerView: UIView {
    var remoteChrome: [RemoteSelectionChrome] = [] {
        didSet {
            guard remoteChrome != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ rect: CGRect) {
        for chrome in remoteChrome {
            chrome.draw()
        }
    }
}
#endif
