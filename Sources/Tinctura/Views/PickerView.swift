import SwiftUI
import AppKit

struct PickerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var capture = ScreenCaptureService()
    @State private var magnifier = MagnifierWindowController()
    @State private var hue: Double = 0.6
    @State private var saturation: Double = 0.7
    @State private var brightness: Double = 0.9
    @State private var hexInput: String = "#5B8DEF"
    @State private var followTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LargeColorPreview(color: appState.currentColor, height: 170)

                pickButtons

                HStack(alignment: .top, spacing: 20) {
                    manualEditor
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FormatCopyRow(color: appState.currentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                recentStrip
            }
            .padding(24)
        }
        .onAppear {
            syncSliders(from: appState.currentColor)
            hexInput = appState.currentColor.hex
            Task { await capture.checkPermission() }
            capture.onColorPicked = { color in
                appState.selectColor(color)
                syncSliders(from: color)
                hexInput = color.hex
                magnifier.hide()
                followTask?.cancel()
            }
            capture.onCancel = {
                magnifier.hide()
                followTask?.cancel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSystemPick)) { _ in
            appState.selectedTab = .picker
            capture.pickWithSystemSampler()
        }
        .onChange(of: appState.currentColor) { _, new in
            syncSliders(from: new)
            hexInput = new.hex
        }
        .onChange(of: capture.magnifierImage) { _, _ in
            if capture.isPicking {
                magnifier.update(capture: capture)
            }
        }
        .onChange(of: capture.cursorPoint) { _, _ in
            if capture.isPicking {
                magnifier.followCursor()
            }
        }
        .onChange(of: capture.zoomLevel) { _, _ in
            if capture.isPicking {
                magnifier.update(capture: capture)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("屏幕取色")
                .font(.title2.weight(.bold))
            Text("系统取色无需权限；放大镜取色需屏幕录制，点击不会穿透，滚轮/捏合可调倍率。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var pickButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    capture.pickWithSystemSampler()
                } label: {
                    Label("系统取色", systemImage: "eyedropper")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    Task {
                        await capture.startMagnifierPick()
                        if capture.isPicking {
                            magnifier.show(capture: capture)
                            startFollowLoop()
                        }
                    }
                } label: {
                    Label(capture.isPicking ? "取色中… Esc 取消" : "放大镜取色", systemImage: "plus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(capture.isPicking)
            }

            HStack(spacing: 8) {
                Image(systemName: capture.hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(capture.hasPermission ? .green : .orange)
                Text(capture.hasPermission ? "已获屏幕录制权限" : "放大镜取色需要屏幕录制权限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !capture.hasPermission {
                    Button("打开设置") { capture.requestPermission() }
                        .font(.caption)
                        .buttonStyle(.link)
                    Button("刷新") {
                        Task { await capture.checkPermission() }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var manualEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手动调节")
                .font(.headline)

            HStack {
                Text("HEX")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                TextField("#RRGGBB", text: $hexInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { applyHex() }
                Button("应用") { applyHex() }
                    .buttonStyle(.bordered)
            }

            sliderRow(title: "H", value: $hue, range: 0...1, tint: .red) {
                applyHSB()
            }
            sliderRow(title: "S", value: $saturation, range: 0...1, tint: .pink) {
                applyHSB()
            }
            sliderRow(title: "B", value: $brightness, range: 0...1, tint: .yellow) {
                applyHSB()
            }

            HStack(spacing: 8) {
                ForEach(["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#007AFF", "#5856D6", "#AF52DE", "#000000", "#FFFFFF"], id: \.self) { hex in
                    ColorSwatchView(color: ColorModel(hex: hex), size: 26, cornerRadius: 6) {
                        let c = ColorModel(hex: hex)
                        appState.selectColor(c)
                        syncSliders(from: c)
                        hexInput = c.hex
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color, onChange: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 16)
            Slider(value: value, in: range) { editing in
                if !editing { onChange() }
            }
            .tint(tint)
            .onChange(of: value.wrappedValue) { _, _ in onChange() }
            Text(String(format: "%.0f", value.wrappedValue * (title == "H" ? 360 : 100)))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近颜色")
                .font(.headline)
            if appState.history.isEmpty {
                Text("取色后将显示在这里")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(appState.history.prefix(20)) { color in
                            ColorSwatchView(
                                color: color,
                                size: 40,
                                selected: color.id == appState.currentColor.id,
                                showHex: true
                            ) {
                                appState.selectColor(color, addToHistory: false)
                            }
                            .contextMenu {
                                Button("复制 \(appState.preferredFormat.rawValue)") {
                                    appState.copy(color.formatted(appState.preferredFormat))
                                }
                                Button("删除", role: .destructive) {
                                    appState.removeHistory(color)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func syncSliders(from color: ColorModel) {
        let hsb = color.hsb
        hue = hsb.h
        saturation = hsb.s
        brightness = hsb.b
    }

    private func applyHSB() {
        let c = ColorModel(
            nsColor: NSColor(
                hue: CGFloat(hue),
                saturation: CGFloat(saturation),
                brightness: CGFloat(brightness),
                alpha: 1
            )
        )
        appState.selectColor(c, addToHistory: false)
        hexInput = c.hex
    }

    private func applyHex() {
        let c = ColorModel(hex: hexInput)
        appState.selectColor(c)
        syncSliders(from: c)
        hexInput = c.hex
    }

    private func startFollowLoop() {
        followTask?.cancel()
        followTask = Task {
            while !Task.isCancelled && capture.isPicking {
                magnifier.followCursor()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}
