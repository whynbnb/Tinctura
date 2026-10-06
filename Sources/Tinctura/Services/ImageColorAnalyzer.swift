import AppKit
import CoreGraphics

struct ExtractedSwatch: Identifiable, Hashable {
    let id = UUID()
    let color: ColorModel
    let population: Int
    let percentage: Double
}

enum ImageColorAnalyzer {
    /// Extract dominant colors using median-cut style quantization + clustering
    static func extractPalette(from image: NSImage, maxColors: Int = 8) -> [ExtractedSwatch] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        return extractPalette(from: cgImage, maxColors: maxColors)
    }

    static func extractPalette(from cgImage: CGImage, maxColors: Int = 8) -> [ExtractedSwatch] {
        let targetSize = 120
        guard let resized = resize(cgImage, maxDimension: targetSize) else { return [] }
        let pixels = samplePixels(resized, step: 1)
        guard !pixels.isEmpty else { return [] }

        // Quantize to reduce noise (5 bits per channel ≈ 32 levels)
        var histogram: [UInt32: Int] = [:]
        histogram.reserveCapacity(min(pixels.count, 4096))
        for p in pixels {
            let key = quantize(p)
            histogram[key, default: 0] += 1
        }

        // Take top candidates then k-means refine
        let sorted = histogram.sorted { $0.value > $1.value }
        let seedCount = min(maxColors * 3, sorted.count)
        var seeds = sorted.prefix(seedCount).map { decode($0.key) }

        // Simple k-means
        let k = min(maxColors, seeds.count)
        if k == 0 { return [] }
        seeds = Array(seeds.prefix(k))

        var centers = seeds
        var assignments = [Int](repeating: 0, count: pixels.count)

        for _ in 0..<12 {
            // Assign
            for (i, p) in pixels.enumerated() {
                var best = 0
                var bestDist = Double.greatestFiniteMagnitude
                for (ci, c) in centers.enumerated() {
                    let d = distance2(p, c)
                    if d < bestDist {
                        bestDist = d
                        best = ci
                    }
                }
                assignments[i] = best
            }
            // Update
            var sums = [(r: 0.0, g: 0.0, b: 0.0, n: 0)]
            sums = Array(repeating: (0, 0, 0, 0), count: k)
            for (i, p) in pixels.enumerated() {
                let a = assignments[i]
                sums[a].r += p.r
                sums[a].g += p.g
                sums[a].b += p.b
                sums[a].n += 1
            }
            for i in 0..<k {
                if sums[i].n > 0 {
                    centers[i] = (
                        sums[i].r / Double(sums[i].n),
                        sums[i].g / Double(sums[i].n),
                        sums[i].b / Double(sums[i].n)
                    )
                }
            }
        }

        // Count populations
        var counts = [Int](repeating: 0, count: k)
        for a in assignments { counts[a] += 1 }
        let total = Double(pixels.count)

        var swatches: [ExtractedSwatch] = []
        for i in 0..<k where counts[i] > 0 {
            let c = centers[i]
            let color = ColorModel(red: c.r, green: c.g, blue: c.b)
            swatches.append(
                ExtractedSwatch(
                    color: color,
                    population: counts[i],
                    percentage: Double(counts[i]) / total
                )
            )
        }

        return swatches.sorted { $0.population > $1.population }
    }

    /// Average color of whole image
    static func averageColor(from image: NSImage) -> ColorModel? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let resized = resize(cg, maxDimension: 64) else { return nil }
        let pixels = samplePixels(resized, step: 1)
        guard !pixels.isEmpty else { return nil }
        var r = 0.0, g = 0.0, b = 0.0
        for p in pixels {
            r += p.r; g += p.g; b += p.b
        }
        let n = Double(pixels.count)
        return ColorModel(red: r / n, green: g / n, blue: b / n)
    }

    /// Color at point in image (normalized 0...1 coords)
    static func color(at normalizedPoint: CGPoint, in image: NSImage) -> ColorModel? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let x = Int(normalizedPoint.x * CGFloat(cg.width))
        let y = Int((1 - normalizedPoint.y) * CGFloat(cg.height))
        return pixelColor(in: cg, x: max(0, min(cg.width - 1, x)), y: max(0, min(cg.height - 1, y)))
    }

    // MARK: - Helpers

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func distance2(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        // Weighted for perceptual similarity
        return 2 * dr * dr + 4 * dg * dg + 3 * db * db
    }

    private static func quantize(_ p: RGB) -> UInt32 {
        let r = UInt32(p.r * 31) & 0x1F
        let g = UInt32(p.g * 31) & 0x1F
        let b = UInt32(p.b * 31) & 0x1F
        return (r << 10) | (g << 5) | b
    }

    private static func decode(_ key: UInt32) -> RGB {
        let r = Double((key >> 10) & 0x1F) / 31
        let g = Double((key >> 5) & 0x1F) / 31
        let b = Double(key & 0x1F) / 31
        return (r, g, b)
    }

    private static func resize(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let w = image.width
        let h = image.height
        let scale = min(1.0, Double(maxDimension) / Double(max(w, h)))
        let nw = max(1, Int(Double(w) * scale))
        let nh = max(1, Int(Double(h) * scale))
        guard let ctx = CGContext(
            data: nil,
            width: nw,
            height: nh,
            bitsPerComponent: 8,
            bytesPerRow: nw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    private static func samplePixels(_ image: CGImage, step: Int) -> [RGB] {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }
        let bpp = max(1, image.bitsPerPixel / 8)
        let bpr = image.bytesPerRow
        var result: [RGB] = []
        result.reserveCapacity((image.width / step) * (image.height / step))
        for y in stride(from: 0, to: image.height, by: step) {
            for x in stride(from: 0, to: image.width, by: step) {
                let o = y * bpr + x * bpp
                let r = Double(ptr[o]) / 255
                let g = Double(ptr[o + 1]) / 255
                let b = Double(ptr[o + 2]) / 255
                let a = bpp > 3 ? Double(ptr[o + 3]) / 255 : 1
                // Skip near-transparent
                if a < 0.15 { continue }
                result.append((r, g, b))
            }
        }
        return result
    }

    private static func pixelColor(in image: CGImage, x: Int, y: Int) -> ColorModel? {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = max(1, image.bitsPerPixel / 8)
        let o = y * image.bytesPerRow + x * bpp
        // resized images use RGBA
        let r = Double(ptr[o]) / 255
        let g = Double(ptr[o + 1]) / 255
        let b = Double(ptr[o + 2]) / 255
        let a = bpp > 3 ? Double(ptr[o + 3]) / 255 : 1
        return ColorModel(red: r, green: g, blue: b, alpha: a)
    }
}
