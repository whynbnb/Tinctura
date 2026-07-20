import AppKit
import SwiftUI

struct ColorModel: Identifiable, Hashable, Codable {
    let id: UUID
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var name: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1.0,
        name: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
        self.name = name
        self.createdAt = createdAt
    }

    init(nsColor: NSColor, name: String = "") {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(c.redComponent),
            green: Double(c.greenComponent),
            blue: Double(c.blueComponent),
            alpha: Double(c.alphaComponent),
            name: name
        )
    }

    init(color: Color, name: String = "") {
        self.init(nsColor: NSColor(color), name: name)
    }

    init(hex: String, name: String = "") {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1
        if h.count == 6 || h.count == 8 {
            let scanner = Scanner(string: h)
            var value: UInt64 = 0
            if scanner.scanHexInt64(&value) {
                if h.count == 8 {
                    r = Double((value & 0xFF00_0000) >> 24) / 255
                    g = Double((value & 0x00FF_0000) >> 16) / 255
                    b = Double((value & 0x0000_FF00) >> 8) / 255
                    a = Double(value & 0x0000_00FF) / 255
                } else {
                    r = Double((value & 0xFF0000) >> 16) / 255
                    g = Double((value & 0x00FF00) >> 8) / 255
                    b = Double(value & 0x0000FF) / 255
                }
            }
        }
        self.init(red: r, green: g, blue: b, alpha: a, name: name)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor)
    }

    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    var isLight: Bool { luminance > 0.55 }

    var contrastingTextColor: Color {
        isLight ? .black : .white
    }

    // MARK: - Formats

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int(red * 255 + 0.5),
            Int(green * 255 + 0.5),
            Int(blue * 255 + 0.5)
        )
    }

    var hexWithAlpha: String {
        String(
            format: "#%02X%02X%02X%02X",
            Int(red * 255 + 0.5),
            Int(green * 255 + 0.5),
            Int(blue * 255 + 0.5),
            Int(alpha * 255 + 0.5)
        )
    }

    var rgbString: String {
        "rgb(\(Int(red * 255 + 0.5)), \(Int(green * 255 + 0.5)), \(Int(blue * 255 + 0.5)))"
    }

    var rgbaString: String {
        String(
            format: "rgba(%d, %d, %d, %.2f)",
            Int(red * 255 + 0.5),
            Int(green * 255 + 0.5),
            Int(blue * 255 + 0.5),
            alpha
        )
    }

    var hsb: (h: Double, s: Double, b: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        switch maxC {
        case red: h = (green - blue) / d + (green < blue ? 6 : 0)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    var hsbString: String {
        let v = hsb
        return String(
            format: "hsb(%.0f°, %.0f%%, %.0f%%)",
            v.h * 360, v.s * 100, v.b * 100
        )
    }

    var hslString: String {
        let v = hsl
        return String(
            format: "hsl(%.0f, %.0f%%, %.0f%%)",
            v.h * 360, v.s * 100, v.l * 100
        )
    }

    var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let k = 1 - max(red, green, blue)
        if k >= 1 { return (0, 0, 0, 1) }
        let c = (1 - red - k) / (1 - k)
        let m = (1 - green - k) / (1 - k)
        let y = (1 - blue - k) / (1 - k)
        return (c, m, y, k)
    }

    var cmykString: String {
        let v = cmyk
        return String(
            format: "cmyk(%.0f%%, %.0f%%, %.0f%%, %.0f%%)",
            v.c * 100, v.m * 100, v.y * 100, v.k * 100
        )
    }

    var swiftUIString: String {
        String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
    }

    var nsColorString: String {
        String(
            format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)",
            red, green, blue, alpha
        )
    }

    var cssHex: String { hex.lowercased() }

    func formatted(_ format: ColorFormat) -> String {
        switch format {
        case .hex: return hex
        case .hexAlpha: return hexWithAlpha
        case .rgb: return rgbString
        case .rgba: return rgbaString
        case .hsb: return hsbString
        case .hsl: return hslString
        case .cmyk: return cmykString
        case .swiftUI: return swiftUIString
        case .nsColor: return nsColorString
        case .css: return cssHex
        }
    }

    // MARK: - Transforms

    func withHSB(h: Double? = nil, s: Double? = nil, b: Double? = nil) -> ColorModel {
        let cur = hsb
        let color = NSColor(
            hue: CGFloat(h ?? cur.h),
            saturation: CGFloat(s ?? cur.s),
            brightness: CGFloat(b ?? cur.b),
            alpha: CGFloat(alpha)
        )
        return ColorModel(nsColor: color, name: name)
    }

    func mixed(with other: ColorModel, amount: Double) -> ColorModel {
        let t = Self.clamp(amount)
        return ColorModel(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    static func random(saturation: ClosedRange<Double> = 0.4...0.9, brightness: ClosedRange<Double> = 0.5...0.95) -> ColorModel {
        ColorModel(
            nsColor: NSColor(
                hue: CGFloat.random(in: 0...1),
                saturation: CGFloat.random(in: CGFloat(saturation.lowerBound)...CGFloat(saturation.upperBound)),
                brightness: CGFloat.random(in: CGFloat(brightness.lowerBound)...CGFloat(brightness.upperBound)),
                alpha: 1
            )
        )
    }

    private static func clamp(_ v: Double) -> Double {
        min(max(v, 0), 1)
    }
}

enum ColorFormat: String, CaseIterable, Identifiable {
    case hex = "HEX"
    case hexAlpha = "HEXA"
    case rgb = "RGB"
    case rgba = "RGBA"
    case hsb = "HSB"
    case hsl = "HSL"
    case cmyk = "CMYK"
    case swiftUI = "SwiftUI"
    case nsColor = "NSColor"
    case css = "CSS"

    var id: String { rawValue }
}
