import AppKit
import Carbon.HIToolbox

/// A global shortcut: a virtual key code plus Carbon modifier flags.
struct KeyShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// Display character, stored so we can render it without a layout table.
    var key: String

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key.uppercased()
    }

    static let defaultModifiers = UInt32(controlKey) | UInt32(shiftKey) | UInt32(cmdKey)

    static let systemPickDefault = KeyShortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: defaultModifiers,
        key: "C"
    )
    static let magnifierPickDefault = KeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: defaultModifiers,
        key: "V"
    )
}

/// Registers global hot keys via Carbon (no accessibility permission required).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private final class Registration {
        var ref: EventHotKeyRef?
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x54494E43), id: id) // 'TINC'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("[Tinctura] global hot key registration failed (%d) for keyCode %u", status, keyCode)
        } else {
            let registration = Registration(action: action)
            registration.ref = ref
            registrations[id] = registration
        }
        return id
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        if let ref = registration.ref {
            UnregisterEventHotKey(ref)
        }
    }

    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in manager.fire(id) }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }
}

/// Persists the two pick shortcuts and keeps their global hot keys registered.
@MainActor
final class ShortcutManager: ObservableObject {
    @Published var systemPick: KeyShortcut {
        didSet {
            guard systemPick != oldValue else { return }
            Self.save(systemPick, to: Self.systemKey)
            register()
        }
    }

    @Published var magnifierPick: KeyShortcut {
        didSet {
            guard magnifierPick != oldValue else { return }
            Self.save(magnifierPick, to: Self.magnifierKey)
            register()
        }
    }

    nonisolated static let systemKey = "settings.shortcut.systemPick"
    nonisolated static let magnifierKey = "settings.shortcut.magnifierPick"

    private var systemID: UInt32?
    private var magnifierID: UInt32?

    init() {
        systemPick = Self.load(from: Self.systemKey) ?? .systemPickDefault
        magnifierPick = Self.load(from: Self.magnifierKey) ?? .magnifierPickDefault
        register()
    }

    private func register() {
        if let systemID { HotKeyManager.shared.unregister(id: systemID) }
        if let magnifierID { HotKeyManager.shared.unregister(id: magnifierID) }

        let system = systemPick
        let magnifier = magnifierPick
        systemID = HotKeyManager.shared.register(keyCode: system.keyCode, modifiers: system.modifiers) {
            AppState.shared.pickSystemColor()
        }
        magnifierID = HotKeyManager.shared.register(keyCode: magnifier.keyCode, modifiers: magnifier.modifiers) {
            AppState.shared.pickMagnifierColor()
        }
    }

    private static func save(_ shortcut: KeyShortcut, to key: String) {
        UserDefaults.standard.set("\(shortcut.keyCode):\(shortcut.modifiers):\(shortcut.key)", forKey: key)
    }

    private static func load(from key: String) -> KeyShortcut? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 3,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else { return nil }
        return KeyShortcut(keyCode: keyCode, modifiers: modifiers, key: String(parts[2]))
    }
}
