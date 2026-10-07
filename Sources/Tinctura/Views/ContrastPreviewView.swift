import SwiftUI
import AppKit

enum ContrastRole: String {
    case foreground = "前景色"
    case background = "背景色"

    var title: String { NSLocalizedString(rawValue, comment: "") }
}

struct ContrastPreviewView: View {
    @EnvironmentObject var appState: AppState

    @State private var foreground = ColorModel(hex: "#1A1A1A")
    @State private var background = ColorModel(hex: "#FFFFFF")
    @State private var activeRole: ContrastRole = .foreground
    @State private var sampleText = "敏捷的棕色狐狸跳过懒狗"
    @State private var fontSize: Double = 16
    @State private var isBold = false

    @StateObject private var capture = ScreenCaptureService()
    @State private var magnifier = MagnifierWindowController()
    @State private var followTask: Task<Void, Never>?

    @State private var fgHex = "#1A1A1A"
    @State private var bgHex = "#FFFFFF"
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0.1

    private var result: WCAGResult {
        WCAGResult.evaluate(foreground: foreground, background: background)
    }

    private var activeColor: ColorModel {
        activeRole == .foreground ? foreground : background
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftPanel
                .frame(minWidth: 380, idealWidth: 460, maxWidth: 580)
            SplitDivider()
                .padding(.horizontal, 20)
            rightPanel
                .frame(minWidth: 440, maxWidth: .infinity)
        }
        .padding(20)
        .onAppear {
            syncEditor(from: activeColor)
            capture.refreshPermissionStatus()
            capture.onColorPicked = { color in
                applyPicked(color)
                magnifier.hide()
                followTask?.cancel()
            }
            capture.onCancel = {
                magnifier.hide()
                followTask?.cancel()
            }
        }
        .onChange(of: capture.magnifierImage) { _, _ in
            if capture.isPicking { magnifier.update(capture: capture) }
        }
        .onChange(of: capture.cursorPoint) { _, _ in
            if capture.isPicking { magnifier.followCursor() }
        }
        .onChange(of: capture.zoomLevel) { _, _ in
            if capture.isPicking { magnifier.update(capture: capture) }
        }
    }

    // MARK: - Left: color slots & picker

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("对比度预览")
                        .font(.title2.weight(.bold))
                    Text("设置前景 / 背景色，实时查看可见性与 WCAG 合规")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                colorSlot(
                    role: .foreground,
                    color: foreground,
                    hex: $fgHex
                )
                colorSlot(
                    role: .background,
                    color: background,
                    hex: $bgHex
                )

                HStack(spacing: 10) {
                    Button {
                        swapColors()
                    } label: {
                        Label("交换前景/背景", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        useCurrentAsActive()
                    } label: {
                        Label("使用当前色", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .help("将侧边栏当前颜色设为选中的角色")
                }

                Divider()

                Text("为「\(activeRole.title)」取色 / 调色")
                    .font(.headline)

                pickButtons

                manualEditor

                if !appState.history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从历史选取")
                            .font(.subheadline.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.history.prefix(24)) { c in
                                    ColorSwatchView(color: c, size: 32, cornerRadius: 6) {
                                        applyPicked(c)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func colorSlot(role: ContrastRole, color: ColorModel, hex: Binding<String>) -> some View {
        let selected = activeRole == role
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(role.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if selected {
                    Text("编辑中")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
            }

            HStack(spacing: 12) {
                Button {
                    selectRole(role)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.swiftUIColor)
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    selected ? Color.accentColor : Color.primary.opacity(0.12),
                                    lineWidth: selected ? 3 : 1
                                )
                        )
                        .shadow(color: color.swiftUIColor.opacity(0.3), radius: selected ? 8 : 2, y: 1)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("#RRGGBB", text: hex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { applyHex(hex.wrappedValue, to: role) }
                        Button("应用") { applyHex(hex.wrappedValue, to: role) }
                            .buttonStyle(.bordered)
                    }
                    Text(color.rgbString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            selectRole(role)
                            capture.pickWithSystemSampler()
                        } label: {
                            Label("屏幕取色", systemImage: "eyedropper")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button {
                            appState.copy(color.formatted(appState.preferredFormat), label: role.rawValue)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectRole(role) }
    }

    private var pickButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    capture.pickWithSystemSampler()
                } label: {
                    Label("系统取色", systemImage: "eyedropper")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task {
                        await capture.startMagnifierPick()
                        if capture.isPicking {
                            magnifier.show(capture: capture)
                            startFollowLoop()
                        }
                    }
                } label: {
                    Label(NSLocalizedString(capture.isPicking ? "取色中… Esc" : "放大镜取色", comment: ""), systemImage: "plus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(capture.isPicking)
            }

            HStack(spacing: 6) {
                Image(systemName: capture.hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(capture.hasPermission ? .green : .orange)
                Text(NSLocalizedString(capture.hasPermission ? "屏幕录制权限已就绪" : "放大镜取色需屏幕录制权限", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !capture.hasPermission {
                    Button("设置") { capture.requestPermission() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
            }
        }
    }

    private var manualEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动调节 (\(activeRole.title))")
                .font(.subheadline.weight(.semibold))

            hsbSlider("H", value: $hue, scale: 360) { applyHSB() }
            hsbSlider("S", value: $saturation, scale: 100) { applyHSB() }
            hsbSlider("B", value: $brightness, scale: 100) { applyHSB() }

            // NSColorPanel style quick pick via SwiftUI ColorPicker
            HStack {
                Text("色板")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { activeColor.swiftUIColor },
                        set: { new in
                            applyPicked(ColorModel(color: new))
                        }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
            }

            HStack(spacing: 8) {
                ForEach(
                    activeRole == .foreground
                        ? ["#000000", "#1A1A1A", "#333333", "#FFFFFF", "#007AFF", "#FF3B30"]
                        : ["#FFFFFF", "#F5F5F7", "#1C1C1E", "#000000", "#E8F0FE", "#FFF3E0"],
                    id: \.self
                ) { hex in
                    ColorSwatchView(color: ColorModel(hex: hex), size: 26, cornerRadius: 6) {
                        applyPicked(ColorModel(hex: hex))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func hsbSlider(_ title: String, value: Binding<Double>, scale: Double, onChange: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 16)
            Slider(value: value, in: 0...1) { editing in
                if !editing { onChange() }
            }
            .onChange(of: value.wrappedValue) { _, _ in onChange() }
            Text(String(format: "%.0f", value.wrappedValue * scale))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Right: preview + WCAG

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Live preview card
                VStack(alignment: .leading, spacing: 16) {
                    Text("实时预览")
                        .font(.headline)
                        .foregroundStyle(foreground.swiftUIColor.opacity(0.7))

                    Text(sampleText)
                        .font(.system(size: fontSize, weight: isBold ? .bold : .regular))
                        .foregroundStyle(foreground.swiftUIColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    Text("The quick brown fox jumps over the lazy dog. 0123456789")
                        .font(.system(size: max(12, fontSize * 0.85), weight: isBold ? .semibold : .regular))
                        .foregroundStyle(foreground.swiftUIColor)

                    HStack(spacing: 12) {
                        previewButton("主要按钮", filled: true)
                        previewButton("次要按钮", filled: false)
                    }

                    // Large text sample
                    Text("大号标题示例")
                        .font(.system(size: max(18, fontSize * 1.5), weight: .bold))
                        .foregroundStyle(foreground.swiftUIColor)
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(background.swiftUIColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

                // Sample controls
                VStack(alignment: .leading, spacing: 10) {
                    TextField("预览文案", text: $sampleText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("字号 \(Int(fontSize))pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $fontSize, in: 12...48, step: 1)
                        Toggle("粗体", isOn: $isBold)
                            .toggleStyle(.checkbox)
                    }
                }

                // Contrast score
                contrastScoreCard

                // WCAG checklist
                wcagChecklist

                // Tips
                if !result.isReadable {
                    Label(
                        "对比度不足：建议加深前景或提高背景明度差，普通文本至少 4.5:1。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                    )
                }
            }
            .padding(.leading, 8)
        }
    }

    private func previewButton(_ title: String, filled: Bool) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? background.swiftUIColor : foreground.swiftUIColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(filled ? foreground.swiftUIColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(foreground.swiftUIColor, lineWidth: filled ? 0 : 1.5)
            )
    }

    private var contrastScoreCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("对比度")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(result.ratioString)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                Text(result.bestLevelLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scoreColor)
            }

            Spacer()

            // Visual meter
            VStack(alignment: .trailing, spacing: 6) {
                contrastMeter
                Text("1 : \(String(format: "%.1f", result.ratio))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var contrastMeter: some View {
        GeometryReader { geo in
            let maxR: Double = 21
            let w = geo.size.width * min(1, result.ratio / maxR)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(scoreColor.gradient)
                    .frame(width: max(6, w))
                // Threshold markers
                ForEach([3.0, 4.5, 7.0], id: \.self) { t in
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 1, height: 14)
                        .offset(x: geo.size.width * t / maxR - 0.5)
                }
            }
        }
        .frame(width: 160, height: 10)
    }

    private var scoreColor: Color {
        if result.passes[.aaaNormal] == true { return .green }
        if result.passes[.aaNormal] == true { return .blue }
        if result.passes[.aaLarge] == true { return .orange }
        return .red
    }

    private var wcagChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WCAG 2.x 合规")
                .font(.headline)

            ForEach(WCAGLevel.allCases) { level in
                let pass = result.passes[level] == true
                HStack(spacing: 12) {
                    Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(pass ? .green : .red.opacity(0.75))
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.title)
                            .font(.body.weight(.medium))
                        Text(level.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(String(format: "≥ %.1f", level.threshold))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(pass ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pass ? Color.green.opacity(0.06) : Color.primary.opacity(0.03))
                )
            }

            Text("大文本：≥ 18pt 常规，或 ≥ 14pt 粗体。UI 组件指图标、边框、输入框等。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func selectRole(_ role: ContrastRole) {
        activeRole = role
        syncEditor(from: activeColor)
    }

    private func applyPicked(_ color: ColorModel) {
        switch activeRole {
        case .foreground:
            foreground = color
            fgHex = color.hex
        case .background:
            background = color
            bgHex = color.hex
        }
        appState.selectColor(color)
        syncEditor(from: color)
    }

    private func applyHex(_ text: String, to role: ContrastRole) {
        let c = ColorModel(hex: text)
        activeRole = role
        applyPicked(c)
        if role == .foreground { fgHex = c.hex } else { bgHex = c.hex }
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
        applyPicked(c)
    }

    private func syncEditor(from color: ColorModel) {
        let hsb = color.hsb
        hue = hsb.h
        saturation = hsb.s
        brightness = hsb.b
        if activeRole == .foreground {
            fgHex = color.hex
        } else {
            bgHex = color.hex
        }
    }

    private func swapColors() {
        let tmp = foreground
        foreground = background
        background = tmp
        fgHex = foreground.hex
        bgHex = background.hex
        syncEditor(from: activeColor)
    }

    private func useCurrentAsActive() {
        applyPicked(appState.currentColor)
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
