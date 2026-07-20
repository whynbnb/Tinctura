import SwiftUI

struct ColorWalkView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var engine = ColorWalkEngine()
    @State private var showTrail = true

    var body: some View {
        HSplitView {
            controls
                .frame(minWidth: 300, idealWidth: 340)
            stage
                .frame(minWidth: 360)
        }
        .padding(16)
        .onAppear {
            engine.setBase(appState.currentColor)
        }
        .onChange(of: engine.current) { _, new in
            appState.selectColor(new, addToHistory: false)
        }
        .onDisappear {
            engine.pause()
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("颜色漫步")
                        .font(.title2.weight(.bold))
                    Text("在色彩空间中自动游走，发现意外之美")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Mode grid
                Text("漫步模式")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(WalkMode.allCases) { mode in
                        modeCard(mode)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    labeledSlider("速度", value: $engine.speed)
                    labeledSlider("步幅", value: $engine.stepSize)
                    Toggle("显示轨迹", isOn: $showTrail)
                }

                if engine.mode == .gradientPath {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("路径端点")
                            .font(.headline)
                        HStack {
                            endpointChip(engine.seedA, label: "A") {
                                engine.seedA = appState.currentColor
                            }
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundStyle(.secondary)
                            endpointChip(engine.seedB, label: "B") {
                                engine.seedB = appState.currentColor
                            }
                        }
                        Text("先选中颜色，再点 A/B 设为端点")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        engine.toggle()
                    } label: {
                        Label(
                            engine.isPlaying ? "暂停" : "开始漫步",
                            systemImage: engine.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(engine.isPlaying ? .orange : .accentColor)

                    Button {
                        engine.stepOnce()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("单步")

                    Button {
                        engine.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("重置")
                }

                HStack(spacing: 10) {
                    Button {
                        engine.setBase(appState.currentColor)
                    } label: {
                        Label("以当前色为起点", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.selectColor(engine.current)
                        appState.copyCurrent()
                    } label: {
                        Label("捕获当前", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    for c in engine.trail.reversed() {
                        appState.pushHistory(c)
                    }
                    appState.toastMessage = "轨迹已写入历史"
                    appState.showCopiedToast = true
                } label: {
                    Label("轨迹全部加入历史", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.link)
            }
            .padding(.trailing, 8)
        }
    }

    private var stage: some View {
        VStack(spacing: 16) {
            ZStack {
                // Ambient background from current color
                LinearGradient(
                    colors: [
                        engine.current.swiftUIColor.opacity(0.55),
                        engine.current.withHSB(h: (engine.current.hsb.h + 0.08).truncatingRemainder(dividingBy: 1)).swiftUIColor.opacity(0.35),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .animation(.easeInOut(duration: 0.35), value: engine.current.hex)

                VStack(spacing: 20) {
                    // Main orb
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        engine.current.swiftUIColor,
                                        engine.current.swiftUIColor.opacity(0.7),
                                        engine.current.withHSB(b: max(0, engine.current.hsb.b - 0.25)).swiftUIColor
                                    ],
                                    center: .topLeading,
                                    startRadius: 10,
                                    endRadius: 140
                                )
                            )
                            .frame(width: 220, height: 220)
                            .shadow(color: engine.current.swiftUIColor.opacity(0.55), radius: 40, y: 10)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                            )
                            .animation(.easeInOut(duration: 0.25), value: engine.current.hex)

                        VStack(spacing: 4) {
                            Text(engine.current.hex)
                                .font(.system(.title, design: .monospaced).weight(.bold))
                            Text(engine.mode.rawValue)
                                .font(.caption.weight(.medium))
                                .opacity(0.85)
                        }
                        .foregroundStyle(engine.current.contrastingTextColor)
                    }

                    // Live formats
                    HStack(spacing: 16) {
                        formatPill(engine.current.rgbString)
                        formatPill(engine.current.hslString)
                    }

                    if showTrail && !engine.trail.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("漫步轨迹")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(engine.trail) { c in
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(c.swiftUIColor)
                                            .frame(width: 28, height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                            )
                                            .onTapGesture {
                                                appState.selectColor(c)
                                                engine.pause()
                                            }
                                            .help(c.hex)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Mode description
            HStack {
                Image(systemName: engine.mode.icon)
                Text(engine.mode.detail)
                    .foregroundStyle(.secondary)
                Spacer()
                if engine.isPlaying {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("漫步中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            .padding(.horizontal, 4)
        }
    }

    private func modeCard(_ mode: WalkMode) -> some View {
        let selected = engine.mode == mode
        return Button {
            engine.mode = mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .frame(width: 18)
                Text(mode.rawValue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(mode.detail)
    }

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }

    private func endpointChip(_ color: ColorModel, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                Text(label)
                    .font(.caption.weight(.bold))
                Text(color.hex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help("用当前颜色设为端点 \(label)")
    }

    private func formatPill(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
    }
}
