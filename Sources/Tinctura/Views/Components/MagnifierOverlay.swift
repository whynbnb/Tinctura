import SwiftUI
import AppKit

/// Floating magnifier window shown during custom screen pick
struct MagnifierOverlayView: View {
    @ObservedObject var capture: ScreenCaptureService

    static let windowSize = CGSize(width: 200, height: 348)
    static let lens: CGFloat = 160
    /// Distance from the top of the overlay to the centre of the lens.
    static let lensCenterFromTop: CGFloat = 8 + lens / 2

    private let contextSize = CGSize(width: 168, height: 105)

    var body: some View {
        VStack(spacing: 8) {
            lensView
            infoCapsule
            context
        }
        .padding(8)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .allowsHitTesting(false)
    }

    private var lensView: some View {
        ZStack {
            if let image = capture.magnifierImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Self.lens, height: Self.lens)
            } else {
                Color.black.opacity(0.35)
                    .frame(width: Self.lens, height: Self.lens)
                    .overlay(ProgressView().controlSize(.small))
            }

            // Pixel grid hint at high zoom
            if capture.zoomLevel >= 10 {
                PixelGridOverlay(cell: Self.lens / max(5, (Self.lens / capture.zoomLevel).rounded()))
                    .opacity(0.12)
                    .frame(width: Self.lens, height: Self.lens)
                    .allowsHitTesting(false)
            }

            // Crosshair
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1, height: Self.lens)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: Self.lens, height: 1)
            Rectangle()
                .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
                .frame(width: 14, height: 14)
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
        .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1).padding(1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private var infoCapsule: some View {
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
    }

    /// Un-magnified crop of the area around the cursor with a marker on the sample point.
    private var context: some View {
        GeometryReader { geo in
            ZStack {
                if let image = capture.contextImage {
                    let fit = fittedRect(imageSize: image.size, in: geo.size)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)

                    marker
                        .position(
                            x: fit.minX + fit.width * capture.contextFraction.x,
                            y: fit.minY + fit.height * capture.contextFraction.y
                        )
                } else {
                    Color.black.opacity(0.5)
                }
            }
        }
        .frame(width: contextSize.width, height: contextSize.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    private var marker: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: 11, height: 11)
            Circle()
                .fill(Color.red)
                .frame(width: 3, height: 3)
        }
        .shadow(color: .black.opacity(0.7), radius: 1)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
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
            hosting.frame = NSRect(origin: .zero, size: MagnifierOverlayView.windowSize)
            self.hosting = hosting

            let win = MagnifierPanel(
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
        let size = window?.frame.size ?? MagnifierOverlayView.windowSize
        // Keep the lens centre exactly on the cursor. Deliberately do NOT
        // clamp to the screen: near the menu bar / edges clamping used to push
        // the lens off the cursor, which both felt wrong and sampled the wrong
        // pixel.
        let lensCenterFromBottom = size.height - MagnifierOverlayView.lensCenterFromTop
        let origin = NSPoint(
            x: p.x - size.width / 2,
            y: p.y - lensCenterFromBottom
        )
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

/// Lets the magnifier sit partly off-screen so its lens can stay centred on the
/// cursor near the menu bar and screen edges instead of being pushed back in.
private final class MagnifierPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
