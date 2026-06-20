#if canImport(AppKit)
import AppKit
import ProseModel

@MainActor final class MacSelectionLayerView: NSView {
    var selection = TextSelection(anchor: 0, head: 0) {
        didSet {
            restartBlinking()
            needsDisplay = true
        }
    }
    var caretRect = CGRect.zero {
        didSet { needsDisplay = true }
    }
    private var editorIsFirstResponder = false {
        didSet {
            restartBlinking()
            needsDisplay = true
        }
    }
    private var caretIsVisible = true {
        didSet { needsDisplay = true }
    }
    nonisolated(unsafe) private(set) var blinkTimer: Timer?

    var drawsCaret: Bool {
        editorIsFirstResponder && caretIsVisible && selection.isCollapsed && !caretRect.isEmpty
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        blinkTimer?.invalidate()
    }

    func setEditorIsFirstResponder(_ isFirstResponder: Bool) {
        editorIsFirstResponder = isFirstResponder
    }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsCaret else { return }
        PlatformColor.label.setFill()
        caretRect.fill()
    }

    private func restartBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        caretIsVisible = true
        guard editorIsFirstResponder, selection.isCollapsed, !caretRect.isEmpty else { return }
        let timer = Timer(timeInterval: Self.systemBlinkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.caretIsVisible.toggle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private static var systemBlinkInterval: TimeInterval {
        let defaults = UserDefaults.standard
        let unified = defaults.double(forKey: "NSTextInsertionPointBlinkPeriod")
        if unified > 0 { return unified / 1_000 }
        let onPeriod = defaults.double(forKey: "NSTextInsertionPointBlinkPeriodOn")
        if onPeriod > 0 { return onPeriod / 1_000 }
        return 0.5
    }
}
#endif
