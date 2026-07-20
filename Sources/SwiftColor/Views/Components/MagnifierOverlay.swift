import SwiftUI
import AppKit

/// Floating magnifier window shown during custom screen pick
struct MagnifierOverlayView: View {
    @ObservedObject var capture: ScreenCaptureService

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image = capture.magnifierImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 160, height: 160)
                } else {
                    Color.black.opacity(0.3)
                        .frame(width: 160, height: 160)
                        .overlay(ProgressView().controlSize(.small))
                }

                // Crosshair
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1, height: 160)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 160, height: 1)
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.4), lineWidth: 1)
                    .frame(width: 12, height: 12)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1).padding(1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            if let color = capture.hoveredColor {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                        )
                    Text(color.hex)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .offset(y: 10)
            }
        }
        .frame(width: 180, height: 210)
        .allowsHitTesting(false)
    }
}

@MainActor
final class MagnifierWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingView<MagnifierOverlayView>?

    func show(capture: ScreenCaptureService) {
        if window == nil {
            let view = MagnifierOverlayView(capture: capture)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 180, height: 210)
            self.hosting = hosting

            let win = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.ignoresMouseEvents = true
            win.hasShadow = false
            win.contentView = hosting
            win.orderFrontRegardless()
            window = win
        } else {
            hosting?.rootView = MagnifierOverlayView(capture: capture)
            window?.orderFrontRegardless()
        }
        followCursor()
    }

    func followCursor() {
        let p = NSEvent.mouseLocation
        // Place magnifier above-right of cursor
        window?.setFrameOrigin(NSPoint(x: p.x + 24, y: p.y + 24))
    }

    func update(capture: ScreenCaptureService) {
        hosting?.rootView = MagnifierOverlayView(capture: capture)
        followCursor()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
