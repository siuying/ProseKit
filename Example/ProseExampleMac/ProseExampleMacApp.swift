import ProseEditor
import ProseModel
import AppKit
import SwiftUI

@main
struct ProseExampleMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MacProseEditorView(document: .macDemo)
                .frame(minWidth: 520, minHeight: 360)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = mainMenu
        }
        guard mainMenu.item(withTitle: "Format") == nil else { return }
        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        formatItem.submenu = MacProseFormatMenu.makeMenu()
        mainMenu.addItem(formatItem)
    }
}

private extension Document {
    static let macDemo = Document(.doc([
        .heading(level: 1, [.text("ProseExample macOS")]),
        .paragraph([
            .text("A native AppKit scroll view renders the shared editor Document through EditorCore."),
        ]),
        .paragraph([
            .text("Highlights render on macOS too: "),
            .text("yellow", marks: [Mark(type: "highlight", attrs: ["color": .string("#ffd54f")])]),
            .text(" and "),
            .text("blue", marks: [Mark(type: "highlight", attrs: ["color": .string("#80d8ff")])]),
            .text("."),
        ]),
        .blockquote([
            .paragraph([.text("The Canvas is content-sized, flipped, and non-layer-backed.")]),
        ]),
        .bulletList([
            .listItem([.paragraph([.text("First macOS list item")])]),
            .listItem([.paragraph([.text("Second macOS list item")])]),
        ]),
    ]))
}
