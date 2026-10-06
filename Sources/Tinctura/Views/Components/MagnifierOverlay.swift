import SwiftUI
import AppKit

/// Floating magnifier window shown during custom screen pick
struct MagnifierOverlayView: View {
    @ObservedObject var capture: ScreenCaptureService

    private let lens: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image = capture.magnifierImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: lens, height: lens)
                } else {
                    Color.black.opacity(0.35)
                        .frame(width: lens, height: lens)
                        .overlay(ProgressView().controlSize(.small))
                }

                // Pixel grid hint at high zoom
                if capture.zoomLevel >= 10 {
                    PixelGridOverlay(cell: lens / max(5, (lens / capture.zoomLevel).rounded()))
                        .opacity(0.12)
                        .frame(width: lens, height: lens)
                        .allowsHitTesting(false)
                }

                // Crosshair
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1, height: lens)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: lens, height: 1)
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1).padding(1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            VStack(spacing: 4) {
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
                }

                Text(String(format: "%.0f× · 滚轮调倍率", capture.zoomLevel))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .offset(y: 10)
        }
        .frame(width: 200, height: 230)
        .allowsHitTesting(false)
    }
}

private struct PixelGridOverlay: View {
    var cell: CGFloat

    var body: some View {
        Canvas { context, size in
            guard cell >= 4 else { return }
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += cell
            }
            context.stroke(path, with: .color(.white), lineWidth: 0.5)
        }
    }
}

@MainActor
final class MagnifierWindowController {
    private var window: NSPanel?
    private var hosting: NSHostingView<MagnifierOverlayView>?

    func show(capture: ScreenCaptureService) {
        if window == nil {
            let view = MagnifierOverlayView(capture: capture)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 230)
            self.hosting = hosting

            let win = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            // Above the event shield (.screenSaver)
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.ignoresMouseEvents = true
            win.hasShadow = false
            win.hidesOnDeactivate = false
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
        // Place magnifier above-right of cursor; keep on-screen if possible
        var origin = NSPoint(x: p.x + 28, y: p.y + 28)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            let size = window?.frame.size ?? NSSize(width: 200, height: 230)
            if origin.x + size.width > f.maxX {
                origin.x = p.x - size.width - 16
            }
            if origin.y + size.height > f.maxY {
                origin.y = p.y - size.height - 16
            }
            origin.x = min(max(origin.x, f.minX), f.maxX - size.width)
            origin.y = min(max(origin.y, f.minY), f.maxY - size.height)
        }
        window?.setFrameOrigin(origin)
    }

    func update(capture: ScreenCaptureService) {
        hosting?.rootView = MagnifierOverlayView(capture: capture)
        followCursor()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
