import Foundation

/// WCAG 2.x contrast ratio & conformance
enum WCAGLevel: String, CaseIterable, Identifiable {
    case aaaNormal = "AAA 正文"
    case aaNormal = "AA 正文"
    case aaaLarge = "AAA 大字"
    case aaLarge = "AA 大字"
    case aaUI = "AA 控件"

    var id: String { rawValue }

    /// Localized display name
    var title: String { NSLocalizedString(rawValue, comment: "") }

    /// Minimum contrast ratio required
    var threshold: Double {
        switch self {
        case .aaaNormal: return 7.0
        case .aaNormal: return 4.5
        case .aaaLarge: return 4.5
        case .aaLarge: return 3.0
        case .aaUI: return 3.0
        }
    }

    var detail: String {
        let key: String
        switch self {
        case .aaaNormal: key = "普通文本 ≥ 7:1"
        case .aaNormal: key = "普通文本 ≥ 4.5:1"
        case .aaaLarge: key = "大文本 ≥ 4.5:1（≥18pt 或 ≥14pt 粗体）"
        case .aaLarge: key = "大文本 ≥ 3:1（≥18pt 或 ≥14pt 粗体）"
        case .aaUI: key = "UI 组件 / 图形对象 ≥ 3:1"
        }
        return NSLocalizedString(key, comment: "")
    }
}

struct WCAGResult: Equatable {
    let ratio: Double
    let passes: [WCAGLevel: Bool]

    var ratioString: String {
        String(format: "%.2f:1", ratio)
    }

    var bestLevelLabel: String {
        if passes[.aaaNormal] == true { return "AAA" }
        if passes[.aaNormal] == true { return "AA" }
        if passes[.aaLarge] == true { return NSLocalizedString("AA 大字", comment: "") }
        return NSLocalizedString("未达标", comment: "")
    }

    var isReadable: Bool {
        passes[.aaNormal] == true || passes[.aaLarge] == true
    }

    static func evaluate(foreground: ColorModel, background: ColorModel) -> WCAGResult {
        let ratio = contrastRatio(foreground, background)
        var map: [WCAGLevel: Bool] = [:]
        for level in WCAGLevel.allCases {
            map[level] = ratio >= level.threshold
        }
        return WCAGResult(ratio: ratio, passes: map)
    }

    /// WCAG relative luminance (sRGB)
    static func relativeLuminance(_ color: ColorModel) -> Double {
        func channel(_ c: Double) -> Double {
            let v = max(0, min(1, c))
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(color.red)
        let g = channel(color.green)
        let b = channel(color.blue)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Contrast ratio (L1 + 0.05) / (L2 + 0.05), always ≥ 1
    static func contrastRatio(_ a: ColorModel, _ b: ColorModel) -> Double {
        // Composite semi-transparent foreground over opaque background
        let fg = composite(foreground: a, background: b)
        let bg = ColorModel(red: b.red, green: b.green, blue: b.blue, alpha: 1)
        let l1 = relativeLuminance(fg)
        let l2 = relativeLuminance(bg)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Alpha-blend foreground over background (both sRGB 0–1)
    private static func composite(foreground: ColorModel, background: ColorModel) -> ColorModel {
        let a = foreground.alpha
        guard a < 1 else {
            return ColorModel(red: foreground.red, green: foreground.green, blue: foreground.blue, alpha: 1)
        }
        let inv = 1 - a
        return ColorModel(
            red: foreground.red * a + background.red * inv,
            green: foreground.green * a + background.green * inv,
            blue: foreground.blue * a + background.blue * inv,
            alpha: 1
        )
    }
}
