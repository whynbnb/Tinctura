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

    private let shield = EventShieldController()

    var onColorPicked: ((ColorModel) -> Void)?
    var onCancel: (() -> Void)?

    /// Silent status check. Never triggers the system permission prompt, so it
    /// is safe to call on view appearance / refresh.
    func refreshPermissionStatus() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    /// Ask the system for screen-recording permission. The system shows its
    /// prompt the first time; call this only from an explicit user action
    /// (e.g. tapping the magnifier button).
    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        hasPermission = granted
        return granted
    }

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
        guard requestScreenRecordingPermission() else {
            requestPermission()
            return
        }
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
            guard let display = content.displays.first else { return }
            self.display = display
            self.displays = content.displays

            // Exclude this process's windows so shield/magnifier never taint sampled pixels
            let myPID = NSRunningApplication.current.processIdentifier
            let exclude = content.windows.filter {
                $0.owningApplication?.processID == myPID
            }

            let filter = SCContentFilter(display: display, excludingWindows: exclude)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.capturesAudio = false

            let output = CaptureOutput()
            output.onFrame = { [weak self] image in
                Task { @MainActor in
                    self?.latestFrame = image
                    self?.updateMagnifier()
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

        let screenHeight = CGFloat(display.height)
        let scaleX = CGFloat(frame.width) / CGFloat(display.width)
        let scaleY = CGFloat(frame.height) / CGFloat(display.height)

        let px = cursorPoint.x * scaleX
        let py = (screenHeight - cursorPoint.y) * scaleY

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

    private func pixelColor(in image: CGImage, atX x: Int, y: Int) -> ColorModel? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = image.bytesPerRow
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard offset + 2 < CFDataGetLength(data) else { return nil }
        // BGRA
        let b = Double(ptr[offset + 0]) / 255
        let g = Double(ptr[offset + 1]) / 255
        let r = Double(ptr[offset + 2]) / 255
        let a = bytesPerPixel > 3 ? Double(ptr[offset + 3]) / 255 : 1
        return ColorModel(red: r, green: g, blue: b, alpha: a)
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
