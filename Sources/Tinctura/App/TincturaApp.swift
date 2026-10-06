import SwiftUI
import AppKit

@main
struct TincturaApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Ensure app activates as a regular GUI app when launched from CLI / SPM
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Tinctura") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("取色") {
                Button("系统取色") {
                    NotificationCenter.default.post(name: .triggerSystemPick, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("复制当前颜色") {
                    appState.copyCurrent()
                }
                .keyboardShortcut("c", modifiers: [.command])

                Divider()

                ForEach(ColorFormat.allCases) { format in
                    Button("复制 \(format.rawValue)") {
                        appState.copyCurrent(format: format)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

extension Notification.Name {
    static let triggerSystemPick = Notification.Name("Tinctura.triggerSystemPick")
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Picker("默认复制格式", selection: $appState.preferredFormat) {
                ForEach(ColorFormat.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)

            Text("屏幕取色 · 图片分析 · 颜色漫步")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360, height: 140)
    }
}
