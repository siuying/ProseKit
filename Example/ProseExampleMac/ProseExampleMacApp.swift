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
        installMenu(title: "Edit", menu: MacProseEditMenu.makeMenu(), in: mainMenu, at: 1)
        installMenu(title: "Format", menu: MacProseFormatMenu.makeMenu(), in: mainMenu, at: 2)
    }

    private func installMenu(title: String, menu: NSMenu, in mainMenu: NSMenu, at index: Int) {
        if let existing = mainMenu.item(withTitle: title) {
            mainMenu.removeItem(existing)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.insertItem(item, at: min(index, mainMenu.items.count))
    }
}

private enum MacProseEditMenu {
    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", action: #selector(ProseView.undo(_:)), key: "z", modifiers: .command))
        menu.addItem(item("Redo", action: #selector(ProseView.redo(_:)), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", action: #selector(ProseView.cut(_:)), key: "x", modifiers: .command))
        menu.addItem(item("Copy", action: #selector(ProseView.copy(_:)), key: "c", modifiers: .command))
        menu.addItem(item("Paste", action: #selector(ProseView.paste(_:)), key: "v", modifiers: .command))
        menu.addItem(.separator())
        menu.addItem(item("Select All", action: #selector(ProseView.selectAll(_:)), key: "a", modifiers: .command))
        return menu
    }

    private static func item(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
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
