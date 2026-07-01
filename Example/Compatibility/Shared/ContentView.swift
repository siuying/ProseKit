import ProseEditor
import SwiftUI
import SwiftYrsHocuspocus

struct ContentView: View {
    @StateObject private var session = EditorSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statusBadge
                Spacer()
                ParticipantsBar(participants: session.participants)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ProseEditorRepresentable(view: session.proseView)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 360)
        #endif
        .task {
            // Test hook: `-autotype "text"` types into the editor a few
            // seconds after launch, so scripts can verify the native→web
            // direction without driving the keyboard.
            guard let text = UserDefaults.standard.string(forKey: "autotype") else { return }
            try? await Task.sleep(for: .seconds(5))
            #if os(iOS)
            session.proseView.insertText(text)
            #else
            session.proseView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            #endif
        }
    }

    private var statusBadge: some View {
        Label(statusText, systemImage: "circle.fill")
            .font(.caption)
            .foregroundStyle(statusColor)
            .labelStyle(.titleAndIcon)
    }

    private var statusText: String {
        switch session.status {
        case .connecting: "connecting…"
        case .connected: "connected"
        case .disconnected: "disconnected"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .connecting: .orange
        case .connected: .green
        case .disconnected: .red
        }
    }
}

struct ParticipantsBar: View {
    let participants: [Participant]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(participants) { participant in
                    Text(participant.isLocal ? "\(participant.name) (you)" : participant.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: participant.color))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

extension Color {
    /// Parses "#rrggbb" chip colors shared with the web peers.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0))).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#if os(iOS)
struct ProseEditorRepresentable: UIViewRepresentable {
    let view: ProseView

    func makeUIView(context: Context) -> ProseView { view }
    func updateUIView(_ uiView: ProseView, context: Context) {}
}
#else
struct ProseEditorRepresentable: NSViewRepresentable {
    let view: ProseView

    func makeNSView(context: Context) -> ProseView { view }
    func updateNSView(_ nsView: ProseView, context: Context) {}
}
#endif
