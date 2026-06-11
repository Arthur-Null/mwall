import AppKit
import Foundation
import ImageIO

struct RGBColor: Codable, Hashable {
    var r: Int
    var g: Int
    var b: Int

    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    var components01: (Double, Double, Double) {
        (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
    }

    var luminance: Double {
        func channel(_ value: Int) -> Double {
            let v = Double(value) / 255.0
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    var hsl: HSLColor {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0
        let maxValue = max(rf, gf, bf)
        let minValue = min(rf, gf, bf)
        let delta = maxValue - minValue
        let l = (maxValue + minValue) / 2.0
        guard delta > 0.0001 else {
            return HSLColor(h: 0, s: 0, l: l)
        }
        let s = delta / (1.0 - abs(2.0 * l - 1.0))
        let h: Double
        if maxValue == rf {
            h = 60.0 * ((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maxValue == gf {
            h = 60.0 * ((bf - rf) / delta + 2.0)
        } else {
            h = 60.0 * ((rf - gf) / delta + 4.0)
        }
        return HSLColor(h: h < 0 ? h + 360.0 : h, s: s, l: l)
    }

    func blended(with other: RGBColor, amount: Double) -> RGBColor {
        let t = min(max(amount, 0.0), 1.0)
        return RGBColor(
            r: Int((Double(r) * (1.0 - t) + Double(other.r) * t).rounded()),
            g: Int((Double(g) * (1.0 - t) + Double(other.g) * t).rounded()),
            b: Int((Double(b) * (1.0 - t) + Double(other.b) * t).rounded())
        )
    }
}

struct HSLColor {
    var h: Double
    var s: Double
    var l: Double

    func shifted(_ degrees: Double) -> HSLColor {
        var next = self
        next.h = (h + degrees).truncatingRemainder(dividingBy: 360.0)
        if next.h < 0 { next.h += 360.0 }
        return next
    }

    func with(saturation: Double? = nil, lightness: Double? = nil) -> HSLColor {
        HSLColor(
            h: h,
            s: min(max(saturation ?? s, 0.0), 1.0),
            l: min(max(lightness ?? l, 0.0), 1.0)
        )
    }

    var rgb: RGBColor {
        let c = (1.0 - abs(2.0 * l - 1.0)) * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = l - c / 2.0
        let segment = Int(h / 60.0)
        let tuple: (Double, Double, Double)
        switch segment {
        case 0: tuple = (c, x, 0)
        case 1: tuple = (x, c, 0)
        case 2: tuple = (0, c, x)
        case 3: tuple = (0, x, c)
        case 4: tuple = (x, 0, c)
        default: tuple = (c, 0, x)
        }
        return RGBColor(
            r: Int(((tuple.0 + m) * 255.0).rounded()).clamped(to: 0...255),
            g: Int(((tuple.1 + m) * 255.0).rounded()).clamped(to: 0...255),
            b: Int(((tuple.2 + m) * 255.0).rounded()).clamped(to: 0...255)
        )
    }
}

struct TerminalPalette: Codable, Equatable {
    var source: RGBColor
    var background: RGBColor
    var foreground: RGBColor
    var cursor: RGBColor
    var cursorText: RGBColor
    var selectionBackground: RGBColor
    var selectionForeground: RGBColor
    var normal: [RGBColor]
    var bright: [RGBColor]
}

struct TerminalPalettePair: Codable, Equatable {
    var dark: TerminalPalette
    var light: TerminalPalette

    var current: TerminalPalette {
        systemPrefersDarkAppearance() ? dark : light
    }
}

enum PaletteGenerator {
    static func generate(from imageURL: URL) throws -> TerminalPalettePair {
        let pixels = try sampledPixels(from: imageURL, size: 72)
        let clusters = kMeans(pixels: pixels, k: 8, iterations: 10)
        let source = pickSourceColor(from: clusters)
        return TerminalPalettePair(
            dark: makeTerminalPalette(source: source, mode: .dark),
            light: makeTerminalPalette(source: source, mode: .light)
        )
    }

    private static func sampledPixels(from imageURL: URL, size: Int) throws -> [RGBColor] {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(domain: "MWall", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取图片"])
        }

        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &bytes,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MWall", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建图片采样上下文"])
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var pixels: [RGBColor] = []
        pixels.reserveCapacity(size * size)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[i + 3] > 20 else { continue }
            pixels.append(RGBColor(r: Int(bytes[i]), g: Int(bytes[i + 1]), b: Int(bytes[i + 2])))
        }
        return pixels
    }

    private struct Cluster {
        var color: RGBColor
        var count: Int
    }

    private static func kMeans(pixels: [RGBColor], k: Int, iterations: Int) -> [Cluster] {
        guard !pixels.isEmpty else {
            return [Cluster(color: RGBColor(r: 84, g: 126, b: 255), count: 1)]
        }

        let buckets = Dictionary(grouping: pixels) { pixel in
            "\(pixel.r / 24)-\(pixel.g / 24)-\(pixel.b / 24)"
        }
        var centroids = buckets
            .sorted { $0.value.count > $1.value.count }
            .prefix(k)
            .map { average($0.value) }
        while centroids.count < k {
            centroids.append(pixels[centroids.count % pixels.count])
        }

        var assignments = Array(repeating: 0, count: pixels.count)
        for _ in 0..<iterations {
            for index in pixels.indices {
                assignments[index] = nearestCentroid(for: pixels[index], centroids: centroids)
            }

            var groups = Array(repeating: [RGBColor](), count: k)
            for (index, pixel) in pixels.enumerated() {
                groups[assignments[index]].append(pixel)
            }
            for index in 0..<k where !groups[index].isEmpty {
                centroids[index] = average(groups[index])
            }
        }

        var counts = Array(repeating: 0, count: k)
        for assignment in assignments {
            counts[assignment] += 1
        }
        return centroids.indices
            .map { Cluster(color: centroids[$0], count: counts[$0]) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    private static func nearestCentroid(for pixel: RGBColor, centroids: [RGBColor]) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, centroid) in centroids.enumerated() {
            let d = distance(pixel, centroid)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func distance(_ a: RGBColor, _ b: RGBColor) -> Double {
        let dr = Double(a.r - b.r)
        let dg = Double(a.g - b.g)
        let db = Double(a.b - b.b)
        return sqrt(dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11)
    }

    private static func average(_ pixels: [RGBColor]) -> RGBColor {
        guard !pixels.isEmpty else { return RGBColor(r: 0, g: 0, b: 0) }
        let total = pixels.reduce((0, 0, 0)) { acc, pixel in
            (acc.0 + pixel.r, acc.1 + pixel.g, acc.2 + pixel.b)
        }
        return RGBColor(r: total.0 / pixels.count, g: total.1 / pixels.count, b: total.2 / pixels.count)
    }

    private static func pickSourceColor(from clusters: [Cluster]) -> RGBColor {
        let scored = clusters.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
        return scored?.color ?? RGBColor(r: 84, g: 126, b: 255)
    }

    private static func score(_ cluster: Cluster) -> Double {
        let hsl = cluster.color.hsl
        let tonePenalty = abs(hsl.l - 0.55) * 1.6
        return pow(Double(cluster.count), 0.38) * (0.35 + hsl.s) * max(0.15, 1.0 - tonePenalty)
    }

    private enum PaletteMode {
        case dark
        case light
    }

    private static func makeTerminalPalette(source: RGBColor, mode: PaletteMode) -> TerminalPalette {
        let hsl = source.hsl
        let baseSaturation = max(0.34, min(0.72, hsl.s))

        let background: RGBColor
        let foreground: RGBColor
        let accent: RGBColor
        let selection: RGBColor
        let black: RGBColor
        let white: RGBColor
        let brightBlack: RGBColor
        let brightWhite: RGBColor

        switch mode {
        case .dark:
            background = hsl.with(saturation: baseSaturation * 0.36, lightness: 0.095).rgb
            foreground = hsl.with(saturation: baseSaturation * 0.24, lightness: 0.88).rgb
            accent = hsl.with(saturation: max(0.50, baseSaturation), lightness: 0.62).rgb
            selection = accent.blended(with: background, amount: 0.32)
            black = hsl.with(saturation: baseSaturation * 0.18, lightness: 0.13).rgb
            white = hsl.with(saturation: baseSaturation * 0.18, lightness: 0.78).rgb
            brightBlack = hsl.with(saturation: baseSaturation * 0.20, lightness: 0.28).rgb
            brightWhite = RGBColor(r: 246, g: 248, b: 255)
        case .light:
            background = hsl.with(saturation: baseSaturation * 0.16, lightness: 0.955).rgb
            foreground = hsl.with(saturation: baseSaturation * 0.28, lightness: 0.145).rgb
            accent = hsl.with(saturation: max(0.48, baseSaturation), lightness: 0.42).rgb
            selection = accent.blended(with: background, amount: 0.70)
            black = hsl.with(saturation: baseSaturation * 0.18, lightness: 0.24).rgb
            white = hsl.with(saturation: baseSaturation * 0.12, lightness: 0.86).rgb
            brightBlack = hsl.with(saturation: baseSaturation * 0.18, lightness: 0.38).rgb
            brightWhite = RGBColor(r: 255, g: 255, b: 255)
        }

        let toneOffset = mode == .dark ? 0.0 : -0.12
        let normal = [
            black,
            color(hue: 4, saturation: 0.64, lightness: 0.56 + toneOffset, tint: hsl.h),
            color(hue: 138, saturation: 0.50, lightness: 0.50 + toneOffset, tint: hsl.h),
            color(hue: 42, saturation: 0.70, lightness: 0.57 + toneOffset, tint: hsl.h),
            color(hue: 218, saturation: 0.62, lightness: 0.62 + toneOffset, tint: hsl.h),
            color(hue: 292, saturation: 0.54, lightness: 0.62 + toneOffset, tint: hsl.h),
            color(hue: 184, saturation: 0.54, lightness: 0.55 + toneOffset, tint: hsl.h),
            white
        ]
        let bright = normal.enumerated().map { index, value in
            if index == 0 { return brightBlack }
            if index == 7 { return brightWhite }
            let c = value.hsl
            let nextLightness = mode == .dark ? min(0.72, c.l + 0.10) : min(0.64, c.l + 0.10)
            return c.with(saturation: min(0.86, c.s + 0.10), lightness: nextLightness).rgb
        }

        return TerminalPalette(
            source: source,
            background: background,
            foreground: foreground,
            cursor: accent,
            cursorText: background,
            selectionBackground: selection,
            selectionForeground: foreground,
            normal: normal,
            bright: bright
        )
    }

    private static func color(hue: Double, saturation: Double, lightness: Double, tint: Double) -> RGBColor {
        let shortest = ((tint - hue + 540.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
        let harmonized = hue + shortest * 0.10
        return HSLColor(
            h: harmonized < 0 ? harmonized + 360.0 : harmonized,
            s: saturation,
            l: min(max(lightness, 0.0), 1.0)
        ).rgb
    }
}

private func systemPrefersDarkAppearance() -> Bool {
    if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
        return style.caseInsensitiveCompare("Dark") == .orderedSame
    }
    return false
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
