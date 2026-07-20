import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: ObservableObject {
    @Published var hasPermission = false
    @Published var isPicking = false
    @Published var magnifierImage: NSImage?
    @Published var hoveredColor: ColorModel?
    @Published var cursorPoint: CGPoint = .zero

    private var stream: SCStream?
    private var streamOutput: CaptureOutput?
    private var display: SCDisplay?
    private var latestFrame: CGImage?
    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    var onColorPicked: ((ColorModel) -> Void)?
    var onCancel: (() -> Void)?

    func checkPermission() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            hasPermission = !content.displays.isEmpty
            display = content.displays.first
        } catch {
            hasPermission = false
        }
    }

    func requestPermission() {
        // Opening Screen Recording settings for the user
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
        await checkPermission()
        guard hasPermission else {
            requestPermission()
            return
        }
        guard !isPicking else { return }
        isPicking = true
        await startStream()
        installMonitors()
        NSCursor.hide()
    }

    func stopMagnifierPick(cancelled: Bool = false) {
        guard isPicking else { return }
        isPicking = false
        NSCursor.unhide()
        removeMonitors()
        stopStream()
        magnifierImage = nil
        hoveredColor = nil
        if cancelled {
            onCancel?()
        }
    }

    private func startStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            self.display = display

            let filter = SCContentFilter(display: display, excludingWindows: [])
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
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "swiftcolor.capture"))
            try await stream.startCapture()
            self.stream = stream
        } catch {
            print("Stream error: \(error)")
            stopMagnifierPick(cancelled: true)
        }
    }

    private func stopStream() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
            latestFrame = nil
        }
    }

    private func installMonitors() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.cursorPoint = NSEvent.mouseLocation
            self?.updateMagnifier()
            return event
        }
        // Also global so we track across spaces
        let globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.cursorPoint = NSEvent.mouseLocation
                self?.updateMagnifier()
            }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.commitPick()
            return nil
        }
        let globalClick = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.commitPick()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.stopMagnifierPick(cancelled: true)
                return nil
            }
            return event
        }
        // Keep references via associated storage on self — store in array
        _extraMonitors = [globalMouse as Any, globalClick as Any].compactMap { $0 }
        _ = globalMouse
        _ = globalClick
    }

    private var _extraMonitors: [Any] = []

    private func removeMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        for m in _extraMonitors { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
        clickMonitor = nil
        keyMonitor = nil
        _extraMonitors = []
    }

    private func commitPick() {
        if let color = hoveredColor {
            onColorPicked?(color)
        }
        stopMagnifierPick()
    }

    private func updateMagnifier() {
        guard isPicking, let frame = latestFrame, let display else { return }

        // Convert Cocoa screen coords (origin bottom-left) to CGImage coords (origin top-left)
        let screenHeight = CGFloat(display.height)
        let scaleX = CGFloat(frame.width) / CGFloat(display.width)
        let scaleY = CGFloat(frame.height) / CGFloat(display.height)

        let px = cursorPoint.x * scaleX
        let py = (screenHeight - cursorPoint.y) * scaleY

        let sampleSize: CGFloat = 15
        let half = sampleSize / 2
        var rect = CGRect(x: px - half, y: py - half, width: sampleSize, height: sampleSize)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        guard rect.width > 1, rect.height > 1,
              let cropped = frame.cropping(to: rect) else { return }

        // Center pixel color
        if let color = pixelColor(in: frame, atX: Int(px), y: Int(py)) {
            hoveredColor = color
        }

        // Upscale for magnifier
        let zoom: CGFloat = 12
        let outW = Int(sampleSize * zoom)
        let outH = Int(sampleSize * zoom)
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
            let nsImage = NSImage(cgImage: cropped, size: NSSize(width: sampleSize, height: sampleSize))
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
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        let offset = y * bytesPerRow + x * bytesPerPixel
        // BGRA
        let b = Double(ptr[offset + 0]) / 255
        let g = Double(ptr[offset + 1]) / 255
        let r = Double(ptr[offset + 2]) / 255
        let a = bytesPerPixel > 3 ? Double(ptr[offset + 3]) / 255 : 1
        return ColorModel(red: r, green: g, blue: b, alpha: a)
    }
}

import CoreMedia
import CoreVideo

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
