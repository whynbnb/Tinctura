import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: ObservableObject {
    @Published var hasPermission = false
    @Published var isPicking = false
    @Published var magnifierImage: NSImage?
    @Published var hoveredColor: ColorModel?
    @Published var cursorPoint: CGPoint = .zero
    /// Small un-magnified crop around the cursor so the user can see the local context.
    @Published var contextImage: NSImage?
    /// Cursor position within `contextImage`, normalized 0...1 (top-left origin).
    @Published var contextFraction: CGPoint = .zero
    /// Source pixels shown in the magnifier (odd). Higher zoom → fewer source pixels, larger scale.
    @Published var zoomLevel: CGFloat = 12

    static let minZoom: CGFloat = 4
    static let maxZoom: CGFloat = 40

    private var stream: SCStream?
    private var streamOutput: CaptureOutput?
    private var display: SCDisplay?
    private var displays: [SCDisplay] = []
    private var latestFrame: CGImage?
    private var keyMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastContextUpdate = Date.distantPast

    private let shield = EventShieldController()

    var onColorPicked: ((ColorModel) -> Void)?
    var onCancel: (() -> Void)?

    /// Silent status check. Never triggers the system permission prompt, so it
    /// is safe to call on view appearance / refresh.
    func refreshPermissionStatus() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    /// Access shareable content, which is what actually triggers the system
    /// screen-recording prompt the first time. We never open System Settings
    /// ourselves here: `CGRequestScreenCaptureAccess` returns before the user
    /// has answered, so jumping to Settings left the system prompt dangling.
    func checkPermission() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            hasPermission = !content.displays.isEmpty
            displays = content.displays
            display = content.displays.first
        } catch {
            hasPermission = false
        }
    }

    /// Opens the Screen Recording pane in System Settings. Only ever called
    /// from the explicit "打开设置" button.
    func requestPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// System eyedropper (no screen recording permission required)
    func pickWithSystemSampler() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] color in
            guard let color else { return }
            let model = ColorModel(nsColor: color)
            Task { @MainActor in
                self?.onColorPicked?(model)
            }
        }
    }

    /// Custom magnifier picker (requires screen recording permission)
    func startMagnifierPick() async {
        // Only here do we ask for permission, so nothing prompts at launch.
        // If access is denied we simply stop — the UI shows a hint with an
        // explicit "打开设置" button instead of opening Settings for the user.
        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
        } else {
            await checkPermission()
        }
        guard hasPermission else { return }
        guard !isPicking else { return }
        isPicking = true
        zoomLevel = 12
        cursorPoint = NSEvent.mouseLocation

        // Full-screen shield swallows clicks so desktop/apps never receive them
        shield.show(
            onMove: { [weak self] point in
                self?.cursorPoint = point
                self?.updateMagnifier()
            },
            onClick: { [weak self] in
                self?.commitPick()
            },
            onScroll: { [weak self] delta in
                self?.adjustZoom(by: delta)
            },
            onCancel: { [weak self] in
                self?.stopMagnifierPick(cancelled: true)
            }
        )

        installKeyMonitor()
        await startStream()
        NSCursor.hide()
        updateMagnifier()
    }

    func stopMagnifierPick(cancelled: Bool = false) {
        guard isPicking else { return }
        isPicking = false
        NSCursor.unhide()
        removeKeyMonitor()
        shield.hide()
        stopStream()
        magnifierImage = nil
        hoveredColor = nil
        contextImage = nil
        contextFraction = .zero
        if cancelled {
            onCancel?()
        }
    }

    func adjustZoom(by scrollDelta: CGFloat) {
        // Trackpad: small deltas; mouse wheel: larger steps (~1 per notch after normalization)
        let step: CGFloat = abs(scrollDelta) < 1 ? scrollDelta * 0.35 : (scrollDelta > 0 ? 1.5 : -1.5)
        // Natural scroll: finger up → positive deltaY on macOS → zoom in
        let next = min(Self.maxZoom, max(Self.minZoom, zoomLevel + step))
        guard abs(next - zoomLevel) > 0.01 else { return }
        zoomLevel = next
        updateMagnifier()
    }

    // MARK: - Stream

    private func startStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Capture the display the pointer is on so the coordinate mapping below is correct.
            guard let display = displayUnderMouse(in: content.displays) ?? content.displays.first else { return }
            self.display = display
            self.displays = content.displays

            // Exclude the whole app rather than a snapshot of its windows: the
            // shield exists now and the magnifier panel is created later, so a
            // per-window list would miss it. With the lens centred on the
            // cursor, missing it means the capture samples the lens itself.
            let myPID = NSRunningApplication.current.processIdentifier
            let myApps = content.applications.filter { $0.processID == myPID }
            let filter = SCContentFilter(display: display, excludingApplications: myApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            // Capture at the display's native pixel resolution. (SCDisplay.width
            // is in points, so using it directly would give a 1x image.)
            config.width = CGDisplayPixelsWide(display.displayID)
            config.height = CGDisplayPixelsHigh(display.displayID)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.capturesAudio = false

            let output = CaptureOutput()
            output.onFrame = { [weak self] image in
                Task { @MainActor in
                    guard let self else { return }
                    self.latestFrame = image
                    self.updateMagnifier()
                }
            }
            streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "tinctura.capture"))
            try await stream.startCapture()
            self.stream = stream
        } catch {
            print("Stream error: \(error)")
            stopMagnifierPick(cancelled: true)
        }
    }

    private func stopStream() {
        let s = stream
        stream = nil
        streamOutput = nil
        latestFrame = nil
        Task {
            try? await s?.stopCapture()
        }
    }

    // MARK: - Key monitor (Escape even if shield loses key)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.stopMagnifierPick(cancelled: true)
                return nil
            }
            // Swallow other keys while picking so they don't hit the app
            return nil
        }
        // Scroll while mouse is over our own app windows (local)
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isPicking else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 3
            self.adjustZoom(by: delta)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = localScrollMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        localScrollMonitor = nil
    }

    private func commitPick() {
        if let color = hoveredColor {
            onColorPicked?(color)
        }
        stopMagnifierPick()
    }

    // MARK: - Magnifier image

    func updateMagnifier() {
        guard isPicking, let frame = latestFrame, let display else { return }

        // CGEvent location and CGDisplayBounds share CoreGraphics' global
        // display space (origin = top-left of the main display, Y grows down),
        // which matches the captured frame's orientation directly.
        let mouse = Self.cgMouseLocation
        let bounds = CGDisplayBounds(display.displayID)
        let scaleX = CGFloat(frame.width) / bounds.width
        let scaleY = CGFloat(frame.height) / bounds.height

        let px = (mouse.x - bounds.minX) * scaleX
        let py = (mouse.y - bounds.minY) * scaleY

        updateContext(from: frame, px: px, py: py)

        // Fixed lens output size; zoomLevel scales how many source pixels fit in the lens
        let lensPixels: CGFloat = 160
        let sampleSize = max(5, min(51, (lensPixels / zoomLevel).rounded(.toNearestOrAwayFromZero)))
        // Keep odd so center pixel aligns with crosshair
        let oddSample = sampleSize.truncatingRemainder(dividingBy: 2) == 0 ? sampleSize + 1 : sampleSize
        let half = oddSample / 2

        var rect = CGRect(x: px - half, y: py - half, width: oddSample, height: oddSample)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        guard rect.width > 1, rect.height > 1,
              let cropped = frame.cropping(to: rect) else { return }

        if let color = pixelColor(in: frame, atX: Int(px.rounded()), y: Int(py.rounded())) {
            hoveredColor = color
        }

        let outW = Int(lensPixels)
        let outH = Int(lensPixels)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outW,
            pixelsHigh: outH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .none
            let nsImage = NSImage(cgImage: cropped, size: NSSize(width: oddSample, height: oddSample))
            nsImage.draw(
                in: NSRect(x: 0, y: 0, width: outW, height: outH),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: outW, height: outH))
        image.addRepresentation(rep)
        magnifierImage = image
    }

    // MARK: - Display / context helpers

    /// Cursor location in CoreGraphics global display space (top-left origin).
    private static var cgMouseLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func displayUnderMouse(in displays: [SCDisplay]) -> SCDisplay? {
        let mouse = Self.cgMouseLocation
        return displays.first { CGDisplayBounds($0.displayID).contains(mouse) }
    }

    /// Builds a small un-magnified crop centered on the cursor.
    private func updateContext(from frame: CGImage, px: CGFloat, py: CGFloat) {
        guard Date().timeIntervalSince(lastContextUpdate) > 0.033 else { return }
        lastContextUpdate = Date()

        let regionW: CGFloat = 200
        let regionH: CGFloat = 125
        var rect = CGRect(x: px - regionW / 2, y: py - regionH / 2, width: regionW, height: regionH)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        guard rect.width > 2, rect.height > 2, let cropped = frame.cropping(to: rect) else { return }

        contextImage = Self.thumbnail(cropped, maxWidth: 360)
        contextFraction = CGPoint(
            x: min(max((px - rect.minX) / rect.width, 0), 1),
            y: min(max((py - rect.minY) / rect.height, 0), 1)
        )
    }

    private static func thumbnail(_ image: CGImage, maxWidth: Int) -> NSImage? {
        let w = maxWidth
        let h = max(1, Int((CGFloat(image.height) / CGFloat(image.width) * CGFloat(w)).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    private func pixelColor(in image: CGImage, atX x: Int, y: Int) -> ColorModel? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        // Render the single pixel into a known RGBA buffer so the source's
        // byte order (BGRA / RGBA / …) doesn't matter.
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ok = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        return ColorModel(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255,
            alpha: Double(pixel[3]) / 255
        )
    }
}

// MARK: - Full-screen event shield (blocks click-through)

@MainActor
final class EventShieldController {
    private var windows: [ShieldPanel] = []

    private var onMove: ((CGPoint) -> Void)?
    private var onClick: (() -> Void)?
    private var onScroll: ((CGFloat) -> Void)?
    private var onCancel: (() -> Void)?

    func show(
        onMove: @escaping (CGPoint) -> Void,
        onClick: @escaping () -> Void,
        onScroll: @escaping (CGFloat) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onMove = onMove
        self.onClick = onClick
        self.onScroll = onScroll
        self.onCancel = onCancel

        for screen in NSScreen.screens {
            let panel = ShieldPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: true)
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.001) // nearly invisible but hit-testable
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none

            let view = ShieldView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onMove = { [weak self] in self?.onMove?(NSEvent.mouseLocation) }
            view.onClick = { [weak self] in self?.onClick?() }
            view.onScroll = { [weak self] d in self?.onScroll?(d) }
            view.onCancel = { [weak self] in self?.onCancel?() }
            panel.contentView = view
            panel.orderFrontRegardless()
            windows.append(panel)
        }

        // Become key so we receive keys / scroll reliably
        windows.first?.makeKey()
        onMove(NSEvent.mouseLocation)
    }

    func hide() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
        onMove = nil
        onClick = nil
        onScroll = nil
        onCancel = nil
    }
}

private final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ShieldView: NSView {
    var onMove: (() -> Void)?
    var onClick: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        onMove?()
    }

    override func mouseDragged(with event: NSEvent) {
        onMove?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Swallow — do not forward to desktop
    }

    override func otherMouseDown(with event: NSEvent) {
        // Swallow
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 4
        if abs(delta) > 0.01 {
            onScroll?(delta)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
        // Swallow all keys while picking
    }

    override func magnify(with event: NSEvent) {
        // Trackpad pinch → zoom
        let delta = CGFloat(event.magnification) * 40
        if abs(delta) > 0.01 {
            onScroll?(delta)
        }
    }
}

// MARK: - Capture output

private final class CaptureOutput: NSObject, SCStreamOutput {
    var onFrame: ((CGImage) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame?(cgImage)
    }
}
