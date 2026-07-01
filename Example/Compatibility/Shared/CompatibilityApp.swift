import ProseEditor
import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct CompatibilityApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(macOS)
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
#endif
