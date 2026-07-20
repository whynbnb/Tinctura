import Foundation
import SwiftUI

/// 颜色漫步：在颜色空间中按多种模式生成连续、优美的色彩轨迹
enum WalkMode: String, CaseIterable, Identifiable {
    case hueSpin = "色相旋转"
    case complementary = "互补跃迁"
    case analogous = "邻近和谐"
    case triad = "三角节奏"
    case pastelDrift = "柔彩漂流"
    case neonPulse = "霓虹脉冲"
    case monoShade = "单色深浅"
    case randomWalk = "随机漫步"
    case gradientPath = "渐变路径"
    case temperature = "冷暖交替"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hueSpin: return "circle.hexagongrid"
        case .complementary: return "arrow.left.arrow.right"
        case .analogous: return "slider.horizontal.3"
        case .triad: return "triangle"
        case .pastelDrift: return "cloud"
        case .neonPulse: return "bolt.fill"
        case .monoShade: return "circle.lefthalf.filled"
        case .randomWalk: return "dice"
        case .gradientPath: return "paintpalette"
        case .temperature: return "thermometer.medium"
        }
    }

    var detail: String {
        switch self {
        case .hueSpin: return "沿色相环匀速旋转"
        case .complementary: return "在互补色之间来回摆动"
        case .analogous: return "在邻近色相中轻柔游走"
        case .triad: return "三角配色节奏切换"
        case .pastelDrift: return "低饱和高明度的柔和漂流"
        case .neonPulse: return "高饱和霓虹感脉冲"
        case .monoShade: return "固定色相，明度起伏"
        case .randomWalk: return "带惯性的随机游走"
        case .gradientPath: return "在两端颜色间往复插值"
        case .temperature: return "冷暖色温交替推进"
        }
    }
}

@MainActor
final class ColorWalkEngine: ObservableObject {
    @Published var mode: WalkMode = .hueSpin
    @Published var isPlaying = false
    @Published var speed: Double = 0.5          // 0...1
    @Published var stepSize: Double = 0.35      // 0...1
    @Published var current: ColorModel
    @Published var trail: [ColorModel] = []
    @Published var seedA: ColorModel
    @Published var seedB: ColorModel
    @Published var pathProgress: Double = 0

    private var timer: Timer?
    private var phase: Double = 0
    private var velocity: (h: Double, s: Double, b: Double) = (0.01, 0, 0)
    private let maxTrail = 48

    init(start: ColorModel = ColorModel(hex: "#5B8DEF")) {
        self.current = start
        self.seedA = start
        self.seedB = start.withHSB(h: (start.hsb.h + 0.5).truncatingRemainder(dividingBy: 1))
        self.trail = [start]
    }

    func setBase(_ color: ColorModel) {
        current = color
        seedA = color
        seedB = color.withHSB(h: (color.hsb.h + 0.33).truncatingRemainder(dividingBy: 1))
        trail = [color]
        phase = 0
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        let interval = max(0.03, 0.2 - speed * 0.16)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func reset() {
        pause()
        setBase(seedA)
    }

    func stepOnce() {
        tick()
    }

    private func tick() {
        let s = 0.2 + stepSize * 1.2
        phase += 0.02 + speed * 0.06

        let next: ColorModel
        switch mode {
        case .hueSpin:
            let h = (current.hsb.h + 0.008 * s + speed * 0.004).truncatingRemainder(dividingBy: 1)
            next = current.withHSB(h: h)

        case .complementary:
            let wave = (sin(phase * 2) + 1) / 2
            let base = seedA.hsb
            let targetH = (base.h + 0.5).truncatingRemainder(dividingBy: 1)
            let h = lerpAngle(base.h, targetH, wave)
            let sat = base.s * (0.75 + 0.25 * sin(phase * 3))
            next = hsbColor(h: h, s: sat, b: base.b)

        case .analogous:
            let base = seedA.hsb
            let spread = 0.08 * s
            let h = (base.h + sin(phase) * spread).truncatingRemainder(dividingBy: 1)
            let wrapped = h < 0 ? h + 1 : h
            next = hsbColor(
                h: wrapped,
                s: min(1, base.s * (0.9 + 0.1 * cos(phase * 1.3))),
                b: min(1, max(0.2, base.b + sin(phase * 0.7) * 0.08))
            )

        case .triad:
            let idx = Int(phase * 0.4 * s) % 3
            let base = seedA.hsb
            let h = (base.h + Double(idx) / 3.0).truncatingRemainder(dividingBy: 1)
            let blend = abs(sin(phase * 1.5))
            let from = current
            let to = hsbColor(h: h, s: base.s, b: base.b)
            next = from.mixed(with: to, amount: 0.15 + blend * 0.2)

        case .pastelDrift:
            let h = (phase * 0.15 * s).truncatingRemainder(dividingBy: 1)
            next = hsbColor(
                h: h,
                s: 0.25 + 0.15 * sin(phase),
                b: 0.88 + 0.08 * cos(phase * 0.8)
            )

        case .neonPulse:
            let h = (phase * 0.2 * s).truncatingRemainder(dividingBy: 1)
            let pulse = (sin(phase * 4) + 1) / 2
            next = hsbColor(
                h: h,
                s: 0.85 + 0.15 * pulse,
                b: 0.7 + 0.3 * pulse
            )

        case .monoShade:
            let base = seedA.hsb
            let b = 0.25 + 0.65 * ((sin(phase * s) + 1) / 2)
            let sat = base.s * (0.6 + 0.4 * ((cos(phase) + 1) / 2))
            next = hsbColor(h: base.h, s: sat, b: b)

        case .randomWalk:
            velocity.h += Double.random(in: -0.01...0.01) * s
            velocity.s += Double.random(in: -0.008...0.008) * s
            velocity.b += Double.random(in: -0.008...0.008) * s
            velocity.h *= 0.96
            velocity.s *= 0.96
            velocity.b *= 0.96
            let cur = current.hsb
            var h = (cur.h + velocity.h).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
            let sat = min(1, max(0.15, cur.s + velocity.s))
            let bri = min(1, max(0.15, cur.b + velocity.b))
            next = hsbColor(h: h, s: sat, b: bri)

        case .gradientPath:
            pathProgress += 0.01 * s * (0.5 + speed)
            let t = (sin(pathProgress * .pi) + 1) / 2
            next = seedA.mixed(with: seedB, amount: t)

        case .temperature:
            // Warm ~0.05 (orange) <-> Cool ~0.55 (blue)
            let t = (sin(phase * s) + 1) / 2
            let h = lerpAngle(0.08, 0.58, t)
            let sat = 0.45 + 0.35 * abs(t - 0.5) * 2
            let bri = 0.65 + 0.2 * (1 - abs(t - 0.5) * 2)
            next = hsbColor(h: h, s: sat, b: bri)
        }

        current = next
        trail.insert(next, at: 0)
        if trail.count > maxTrail {
            trail = Array(trail.prefix(maxTrail))
        }
    }

    private func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var d = b - a
        if d > 0.5 { d -= 1 }
        if d < -0.5 { d += 1 }
        var r = a + d * t
        if r < 0 { r += 1 }
        if r >= 1 { r -= 1 }
        return r
    }

    private func hsbColor(h: Double, s: Double, b: Double) -> ColorModel {
        ColorModel(
            nsColor: NSColor(
                hue: CGFloat(h),
                saturation: CGFloat(min(1, max(0, s))),
                brightness: CGFloat(min(1, max(0, b))),
                alpha: 1
            )
        )
    }
}

import AppKit
