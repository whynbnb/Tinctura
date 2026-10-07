import SwiftUI
import AppKit

@main
struct TincturaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var language = LanguageManager()
    @StateObject private var appearance = AppearanceManager()
    @StateObject private var menuBar = MenuBarManager()

    init() {
        // Ensure app activates as a regular GUI app when launched from CLI / SPM.
        // In menu bar mode the app is an accessory (no Dock icon).
        let menuBarOn = UserDefaults.standard.bool(forKey: MenuBarManager.defaultsKey)
        NSApplication.shared.setActivationPolicy(menuBarOn ? .accessory : .regular)
    }

    var body: some Scene {
        WindowGroup("Tinctura", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(language)
                .environmentObject(appearance)
                .environmentObject(menuBar)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .id(language.language)
                .frame(minWidth: 1160, minHeight: 780)
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Tinctura") { showAboutPanel() }
            }

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

        // NOTE: menu bar mode is implemented with an AppKit `NSStatusItem`
        // (see `MenuBarManager`). We deliberately do NOT use SwiftUI's
        // `MenuBarExtra` scene here: adding it to `body` enlarged the opaque
        // `App.Body` type, and Swift's runtime then recursed while instantiating
        // its opaque-type metadata (`buildDescriptorPath`), overflowing the stack.

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(language)
                .environmentObject(appearance)
                .environmentObject(menuBar)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .id(language.language)
        }
    }

    /// Standard About panel with the project link and MIT license.
    @MainActor
    private func showAboutPanel() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let repoString = "https://github.com/whynbnb/Tinctura"
        let licenseString = "https://github.com/whynbnb/Tinctura/blob/main/LICENSE"

        func link(_ text: String, _ urlString: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .link: URL(string: urlString)!,
                .paragraphStyle: paragraph
            ])
        }
        func line(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text + "\n", attributes: [.font: font, .paragraphStyle: paragraph])
        }

        let credits = NSMutableAttributedString()
        credits.append(link(repoString, repoString))
        credits.append(line(""))
        credits.append(link(NSLocalizedString("MIT 许可证", comment: ""), licenseString))
        credits.append(line(""))
        credits.append(NSAttributedString(
            string: "Copyright © 2026 0x574859",
            attributes: [.font: font, .paragraphStyle: paragraph]
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tinctura",
            .applicationVersion: shortVersion,
            .credits: credits
        ])
    }
}

extension Notification.Name {
    static let triggerSystemPick = Notification.Name("Tinctura.triggerSystemPick")
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: LanguageManager
    @EnvironmentObject var appearance: AppearanceManager
    @EnvironmentObject var menuBar: MenuBarManager

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

            Toggle("菜单栏模式", isOn: $menuBar.isEnabled)
            Text("在菜单栏显示图标并隐藏 Dock 图标；关闭窗口后仍在菜单栏运行。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("显示色值", isOn: $menuBar.showValue)
                .disabled(!menuBar.isEnabled)

            Picker("菜单栏图标", selection: $menuBar.icon) {
                ForEach(MenuBarIconPreset.allCases) { preset in
                    if let symbol = preset.symbolName {
                        Label(preset.label, systemImage: symbol).tag(preset)
                    } else {
                        Text(preset.label).tag(preset)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(!menuBar.isEnabled)

            Text("屏幕取色 · 图片分析 · 颜色漫步")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 400, height: 430)
    }
}
