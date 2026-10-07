import SwiftUI
import AppKit
import ObjectiveC
import Combine

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    /// The localization actually used for bundle lookups.
    var resolvedCode: String {
        switch self {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    var localeIdentifier: String { resolvedCode == "zh-Hans" ? "zh-Hans" : "en" }
}

/// Redirects `Bundle.main` string lookups to the selected language so that
/// SwiftUI's `Text("…")` keys resolve at runtime without a relaunch.
///
/// We swizzle `Bundle.localizedString(forKey:value:table:)` instead of
/// swapping `Bundle.main`'s class at runtime (`object_setClass`). Replacing the
/// class of a live Foundation object corrupts its Objective-C runtime metadata
/// and can crash the process (and makes the debugger unable to read class data).
enum LocalizationRuntime {
    private nonisolated(unsafe) static var installed = false
    nonisolated(unsafe) static var language = "en"

    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(Bundle.localizedString(forKey:value:table:))
        let replacement = #selector(Bundle.tinctura_localizedString(forKey:value:table:))
        guard let a = class_getInstanceMethod(Bundle.self, original),
              let b = class_getInstanceMethod(Bundle.self, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

extension Bundle {
    @objc func tinctura_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if self == Bundle.main,
           let path = Bundle.main.path(forResource: LocalizationRuntime.language, ofType: "lproj"),
           let localized = Bundle(path: path) {
            // After the swizzle this selector runs the original Foundation code.
            return localized.tinctura_localizedString(forKey: key, value: value, table: tableName)
        }
        return tinctura_localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            apply(store: true)
        }
    }

    private static let defaultsKey = "settings.language"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = AppLanguage(rawValue: saved ?? "") ?? .system
        apply(store: false)
    }

    var localeIdentifier: String { language.localeIdentifier }

    private func apply(store: Bool) {
        LocalizationRuntime.language = language.resolvedCode
        LocalizationRuntime.install()
        if store {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Menu Bar

/// Menu bar mode: an AppKit `NSStatusItem` with a small action menu.
///
/// This intentionally does not use SwiftUI's `MenuBarExtra` scene. Putting that
/// scene in `TincturaApp.body` enlarged the opaque `App.Body` type, and Swift's
/// runtime then recursed while instantiating the opaque-type metadata
/// (`swift_getOpaqueTypeMetadataImpl` → `buildDescriptorPath`), overflowing the
/// stack. A plain status item avoids the SwiftUI scene graph entirely.
@MainActor
final class MenuBarManager: NSObject, ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            applyPolicy()
            updateStatusItem()
            if !isEnabled {
                // Leaving menu bar mode: bring the main window back.
                appState.showMainWindow()
            }
        }
    }

    nonisolated static let defaultsKey = "settings.menuBar"
    /// Whether the main window was on screen the last time the app was used.
    nonisolated static let windowShownKey = "settings.windowShown"

    private let appState = AppState.shared
    private var statusItem: NSStatusItem?
    private var colorSink: AnyCancellable?

    override init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        super.init()
        colorSink = appState.$currentColor
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Installs the status item if menu bar mode is on. Safe to call repeatedly.
    func start() {
        updateStatusItem()
    }

    // MARK: Status item

    private func updateStatusItem() {
        if isEnabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageOnly
            item.menu = makeMenu()
            statusItem = item
        }
        refresh()
    }

    private func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func refresh() {
        guard let button = statusItem?.button else { return }
        button.image = Self.swatch(for: appState.currentColor)
        statusItem?.menu?.item(at: 0)?.title = copyTitle()
    }

    /// Accessory apps live in the menu bar only (no Dock icon) and keep running
    /// after the main window closes; regular apps behave like a normal windowed app.
    /// The policy follows whether the main window is currently shown, so opening
    /// the window puts the app back in the Dock.
    private func applyPolicy() {
        Task { @MainActor in appState.updateActivationPolicy() }
    }

    // MARK: Icon

    static func swatch(for color: ColorModel, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset: CGFloat = 3.5
            let box = rect.insetBy(dx: inset, dy: inset)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            color.nsColor.setFill()
            path.fill()
            (color.isLight ? NSColor.black : NSColor.white)
                .withAlphaComponent(0.35)
                .setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Menu

    private func copyTitle() -> String {
        appState.currentColor.formatted(appState.preferredFormat)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // No key equivalents are attached to any item in this menu: the menu bar
        // menu must not listen for / react to app shortcuts (⌘, ⌘Q …). Those
        // remain available only from the app's main menu when a window is focused.

        let copy = NSMenuItem(title: copyTitle(), action: #selector(copyCurrent), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)

        let copyAs = NSMenuItem(title: NSLocalizedString("复制为", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for format in ColorFormat.allCases {
            let item = NSMenuItem(title: format.rawValue, action: #selector(copyFormat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format.rawValue
            submenu.addItem(item)
        }
        copyAs.submenu = submenu
        menu.addItem(copyAs)

        menu.addItem(.separator())

        let pick = NSMenuItem(title: NSLocalizedString("系统取色", comment: ""), action: #selector(pickSystem), keyEquivalent: "")
        pick.target = self
        menu.addItem(pick)

        menu.addItem(.separator())

        let open = NSMenuItem(title: NSLocalizedString("打开主窗口", comment: ""), action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        // Selector is intentionally NOT `openSettings`/`showSettingsWindow:`:
        // AppKit auto-attaches a gear symbol to those actions.
        let settings = NSMenuItem(title: NSLocalizedString("设置…", comment: ""), action: #selector(openPreferences), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: NSLocalizedString("退出 Tinctura", comment: ""), action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func copyCurrent() {
        appState.copyCurrent()
    }

    @objc private func copyFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = ColorFormat(rawValue: raw) else { return }
        appState.copyCurrent(format: format)
    }

    @objc private func pickSystem() {
        appState.pickSystemColor()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        appState.showMainWindow()
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        appState.requestOpenSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .light: return NSLocalizedString("浅色", comment: "")
        case .dark: return NSLocalizedString("深色", comment: "")
        }
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            apply(store: true)
        }
    }

    private static let defaultsKey = "settings.appearance"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        appearance = AppAppearance(rawValue: saved ?? "") ?? .system
        apply(store: false)
    }

    private func apply(store: Bool) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if store {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.defaultsKey)
        }
    }
}
