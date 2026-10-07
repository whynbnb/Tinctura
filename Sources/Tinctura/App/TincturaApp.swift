import SwiftUI
import AppKit

@main
struct TincturaApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var language = LanguageManager()
    @StateObject private var appearance = AppearanceManager()

    init() {
        // Ensure app activates as a regular GUI app when launched from CLI / SPM
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Tinctura") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(language)
                .environmentObject(appearance)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .id(language.language)
                .frame(minWidth: 1160, minHeight: 780)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1360, height: 880)
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
                .environmentObject(language)
                .environmentObject(appearance)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .id(language.language)
        }
    }
}

extension Notification.Name {
    static let triggerSystemPick = Notification.Name("Tinctura.triggerSystemPick")
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: LanguageManager
    @EnvironmentObject var appearance: AppearanceManager

    var body: some View {
        Form {
            Picker("外观", selection: $appearance.appearance) {
                ForEach(AppAppearance.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)

            Picker("语言", selection: $language.language) {
                ForEach(AppLanguage.allCases) { l in
                    Text(l.label).tag(l)
                }
            }
            .pickerStyle(.segmented)

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
        .frame(width: 400, height: 260)
    }
}
