import SwiftUI
import AppKit

/// Shows a key shortcut and records a new one when clicked.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? NSLocalizedString("按下快捷键…", comment: "") : shortcut.displayString)
                .font(.system(.body, design: .rounded).monospaced())
                .frame(minWidth: 92, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { isRecording = true }

            if isRecording {
                Button(NSLocalizedString("取消", comment: "")) { isRecording = false }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .background(
            ShortcutCaptureView(
                isRecording: isRecording,
                onCapture: { newValue in
                    shortcut = newValue
                    isRecording = false
                },
                onCancel: { isRecording = false }
            )
            .frame(width: 0, height: 0)
        )
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    var isRecording: Bool
    var onCapture: (KeyShortcut) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.isRecording = isRecording
    }
}

final class ShortcutCaptureNSView: NSView {
    var onCapture: ((KeyShortcut) -> Void)?
    var onCancel: (() -> Void)?

    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                window?.makeFirstResponder(self)
            } else if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Escape
            onCancel?()
            return
        }
        let modifiers = KeyShortcut.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return
        }
        onCapture?(KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
    }
}
