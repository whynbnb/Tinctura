import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// The app is single-instance, so the menu bar controller and the SwiftUI
    /// scene graph can share one state object.
    static let shared = AppState()

    enum Tab: String, CaseIterable, Identifiable {
        case picker = "屏幕取色"
        case contrast = "对比度"
        case analyzer = "图片分析"
        case walk = "颜色漫步"
        case history = "历史"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .picker: return "eyedropper"
            case .contrast: return "circle.lefthalf.filled"
            case .analyzer: return "photo.on.rectangle.angled"
            case .walk: return "waveform.path"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    @Published var selectedTab: Tab = .picker
    @Published var currentColor: ColorModel = ColorModel(hex: "#5B8DEF")
    @Published var history: [ColorModel] = []
    @Published var preferredFormat: ColorFormat = .hex
    @Published var showCopiedToast = false
    @Published var toastMessage = ""

    private let historyKey = "Tinctura.history"
    private let maxHistory = 80

    init() {
        loadHistory()
    }

    func selectColor(_ color: ColorModel, addToHistory: Bool = true) {
        currentColor = color
        if addToHistory {
            pushHistory(color)
        }
    }

    func pushHistory(_ color: ColorModel) {
        if let first = history.first,
           abs(first.red - color.red) < 0.002,
           abs(first.green - color.green) < 0.002,
           abs(first.blue - color.blue) < 0.002 {
            return
        }
        history.insert(color, at: 0)
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
        saveHistory()
    }

    func removeHistory(_ color: ColorModel) {
        history.removeAll { $0.id == color.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func copy(_ text: String, label: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let format = NSLocalizedString("已复制 %@", comment: "")
        toastMessage = String(format: format, label ?? text)
        showCopiedToast = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            showCopiedToast = false
        }
    }

    func copyCurrent(format: ColorFormat? = nil) {
        let f = format ?? preferredFormat
        copy(currentColor.formatted(f), label: f.rawValue)
    }

    /// System eyedropper that works without the main window (e.g. from menu bar mode).
    func pickSystemColor() {
        let sampler = NSColorSampler()
        sampler.show { color in
            guard let color else { return }
            Task { @MainActor in
                self.selectColor(ColorModel(nsColor: color))
            }
        }
    }

    // MARK: - Main window

    /// Captured from a SwiftUI view so the AppKit status item can drive the window.
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?
    private var didHandleLaunchWindow = false
    private var windowObservers: [NSObjectProtocol] = []

    /// Set by the app delegate while the app is quitting, so window teardown is
    /// not mistaken for the user closing the window.
    var isTerminating = false

    weak var mainWindow: NSWindow?

    var isMenuBarMode: Bool {
        UserDefaults.standard.bool(forKey: MenuBarManager.defaultsKey)
    }

    /// Whether the main window should be shown at launch. Menu bar mode with no
    /// main window remembered stays in the menu bar; otherwise the window shows.
    private var rememberedWindowShown: Bool {
        UserDefaults.standard.object(forKey: MenuBarManager.windowShownKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: MenuBarManager.windowShownKey)
    }

    private func persistWindowShown(_ shown: Bool) {
        UserDefaults.standard.set(shown, forKey: MenuBarManager.windowShownKey)
    }

    /// Regular (Dock icon) while a main window is on screen or minimized;
    /// accessory (menu bar only, no Dock icon) when menu bar mode is on and the
    /// main window is hidden or closed.
    func updateActivationPolicy() {
        let hasWindow = NSApp.windows.contains { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = (isMenuBarMode && !hasWindow) ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Called from a SwiftUI view when it is attached to its window. This runs
    /// before the window is shown, so we can hide it in menu bar mode without
    /// flashing the window on screen.
    func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        observeWindow(window)

        if !didHandleLaunchWindow {
            didHandleLaunchWindow = true
            let shouldShow = !isMenuBarMode || rememberedWindowShown
            persistWindowShown(shouldShow)
            if !shouldShow {
                // Menu bar only: hide before the first frame.
                window.alphaValue = 0
                DispatchQueue.main.async {
                    window.orderOut(nil)
                    self.updateActivationPolicy()
                }
                return
            }
        }
        DispatchQueue.main.async { self.updateActivationPolicy() }
    }

    func showMainWindow() {
        if let window = mainWindow {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
        persistWindowShown(true)
        updateActivationPolicy()
    }

    private func observeWindow(_ window: NSWindow) {
        guard windowObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let immediate: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        for name in immediate {
            windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateActivationPolicy() }
            })
        }
        // `willClose` fires before the window is gone, so re-check shortly after.
        windowObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Closing a window as part of quitting is not a state change.
                if !self.isTerminating {
                    self.persistWindowShown(false)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.updateActivationPolicy()
            }
        })
    }

    /// Captured from a SwiftUI view (`openWindow`) so the AppKit status item can
    /// recreate the main window after it has been closed.
    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func requestOpenMainWindow() {
        openMainWindowAction?()
    }

    /// Captured from a SwiftUI view (`openSettings`).
    func setOpenSettingsAction(_ action: @escaping () -> Void) {
        openSettingsAction = action
    }

    func requestOpenSettings() {
        openSettingsAction?()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([ColorModel].self, from: data) else { return }
        history = items
        if let first = items.first {
            currentColor = first
        }
    }
}
