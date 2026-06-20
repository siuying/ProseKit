import ProseEditor
import ProseModel
import SwiftUI

@main
struct ProseExampleMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacProseEditorView(document: .macDemo)
                .frame(minWidth: 520, minHeight: 360)
        }
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
    ]))
}
