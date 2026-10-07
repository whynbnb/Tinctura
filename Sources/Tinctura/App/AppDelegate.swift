import AppKit

/// App lifecycle hooks for menu bar mode.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarEnabled: Bool {
        UserDefaults.standard.bool(forKey: MenuBarManager.defaultsKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if menuBarEnabled {
            // Menu bar mode: run as an accessory app (no Dock icon).
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // In menu bar mode the app keeps living in the status bar.
        !menuBarEnabled
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Let AppState know the window teardown below is not a user action.
        AppState.shared.isTerminating = true
    }
}
