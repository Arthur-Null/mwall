// Wallpaper-derived multi-color palettes.
// OKLab transforms: https://bottosson.github.io/posts/oklab/ (public domain).
import AppKit
import Foundation
import ImageIO

struct OKColor {
    var l: Double
    var a: Double
    var b: Double
    init(_ color: RGBColor) {
        func linear(_ v: Int) -> Double {
            let x = Double(v) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let r = linear(color.r)
        let g = linear(color.g)
        let b = linear(color.b)
        let x = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let y = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let z = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        l = 0.2104542553 * x + 0.7936177850 * y - 0.0040720468 * z
        a = 1.9779984951 * x - 2.4285922050 * y + 0.4505937099 * z
        self.b = 0.0259040371 * x + 0.7827717662 * y - 0.8086757660 * z
    }
    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }
    var chroma: Double { hypot(a, b) }
    var hue: Double { (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
    func distance(_ other: OKColor) -> Double {
        pow(l - other.l, 2) + pow(a - other.a, 2) + pow(b - other.b, 2)
    }
    func at(_ lightness: Double, chroma: Double? = nil) -> OKColor {
        let scale = (chroma ?? self.chroma) / max(self.chroma, 0.000001)
        return OKColor(l: lightness, a: a * scale, b: b * scale)
    }
    private var linearRGB: [Double] {
        let x = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let y = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let z = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return [
            4.0767416621 * x - 3.3077115913 * y + 0.2309699292 * z,
            -1.2684380046 * x + 2.6097574011 * y - 0.3413193965 * z,
            -0.0041960863 * x - 0.7034186147 * y + 1.7076147010 * z,
        ]
    }
    var rgb: RGBColor {
        // Reduce chroma, preserving hue and lightness, to fit sRGB.
        var color = self
        if linearRGB.contains(where: { $0 < -0.00001 || $0 > 1.00001 }) {
            var lo = 0.0
            var hi = chroma
            for _ in 0..<22 {
                let mid = (lo + hi) / 2
                let candidate = at(l, chroma: mid)
                if candidate.linearRGB.allSatisfy({ $0 >= 0 && $0 <= 1 }) { lo = mid } else { hi = mid }
            }
            color = at(l, chroma: lo)
        }
        func encode(_ x: Double) -> Int {
            let v = min(1, max(0, x))
            let srgb = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            return Int((srgb * 255).rounded())
        }
        let channels = color.linearRGB.map(encode)
        return RGBColor(r: channels[0], g: channels[1], b: channels[2])
    }
}

func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
    // WCAG relative luminance after sRGB decoding.
    func luminance(_ c: RGBColor) -> Double {
        func linear(_ v: Int) -> Double {
            let x = Double(v) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
    let x = luminance(a)
    let y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

func readable(_ color: RGBColor, on background: RGBColor, ratio: Double, dark: Bool) -> RGBColor {
    if contrast(color, background) >= ratio { return color }
    let source = OKColor(color)
    let end = dark ? 1.0 : 0.0
    // Keep hue; find the smallest movement toward the readable endpoint.
    var lo = 0.0
    var hi = 1.0
    for _ in 0..<24 {
        let t = (lo + hi) / 2
        let candidate = source.at(source.l + (end - source.l) * t).rgb
        if contrast(candidate, background) >= ratio + 0.02 { hi = t } else { lo = t }
    }
    return source.at(source.l + (end - source.l) * hi).rgb
}

struct ImageSwatch: Codable {
    let hex: String
    let share: Double
}
struct SampleCluster {
    let color: RGBColor
    let count: Int
    var lab: OKColor { OKColor(color) }
}

enum PerceptualPalette {
    static func clusters(from url: URL) throws -> [SampleCluster] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 192,
                ] as CFDictionary)
        else { throw NSError(domain: "MWall.Palette", code: 1) }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw NSError(domain: "MWall.Palette", code: 2) }
        var pixels: [RGBColor] = []
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] >= 128 {
            let alpha = Double(bytes[i + 3]) / 255
            pixels.append(
                RGBColor(
                    r: min(255, Int(Double(bytes[i]) / alpha)),
                    g: min(255, Int(Double(bytes[i + 1]) / alpha)),
                    b: min(255, Int(Double(bytes[i + 2]) / alpha))))
        }
        guard !pixels.isEmpty else {
            return [SampleCluster(color: RGBColor(r: 128, g: 128, b: 128), count: 1)]
        }
        let labs = pixels.map(OKColor.init)
        // Deterministic farthest-point seeds, with population weighting to avoid tiny noise clusters.
        let bucketed = Dictionary(grouping: pixels.indices) { i in
            (pixels[i].r / 16) * 256 + (pixels[i].g / 16) * 16 + pixels[i].b / 16
        }.sorted {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }
        var centers = [labs[bucketed[0].value[0]]]
        while centers.count < min(32, bucketed.count) {
            let candidate = bucketed.max { x, y in
                func score(_ indices: [Int]) -> Double {
                    let c = labs[indices[0]]
                    return centers.map { c.distance($0) }.min()! * sqrt(Double(indices.count))
                }
                return score(x.value) < score(y.value)
            }!
            let c = labs[candidate.value[0]]
            if centers.contains(where: { c.distance($0) < 1e-12 }) { break }
            centers.append(c)
        }
        var assignments = [Int](repeating: 0, count: labs.count)
        for _ in 0..<10 {
            var sums = [(Double, Double, Double, Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for i in labs.indices {
                var best = 0
                var d = Double.infinity
                for j in centers.indices {
                    let next = labs[i].distance(centers[j])
                    if next < d {
                        d = next
                        best = j
                    }
                }
                assignments[i] = best
                sums[best].0 += labs[i].l
                sums[best].1 += labs[i].a
                sums[best].2 += labs[i].b
                sums[best].3 += 1
            }
            for j in centers.indices where sums[j].3 > 0 {
                let n = Double(sums[j].3)
                centers[j] = OKColor(l: sums[j].0 / n, a: sums[j].1 / n, b: sums[j].2 / n)
            }
        }
        // Select a real sampled pixel nearest each centroid, not an invented average color.
        var groups = [[Int]](repeating: [], count: centers.count)
        for i in labs.indices {
            let best = centers.indices.min {
                labs[i].distance(centers[$0]) < labs[i].distance(centers[$1])
            }!
            groups[best].append(i)
        }
        return centers.indices.compactMap { j -> SampleCluster? in
            guard
                let i = groups[j].min(by: { labs[$0].distance(centers[j]) < labs[$1].distance(centers[j]) })
            else { return nil }
            return SampleCluster(color: pixels[i], count: groups[j].count)
        }.sorted { $0.count == $1.count ? $0.color.hex < $1.color.hex : $0.count > $1.count }
    }

    static func pair(_ clusters: [SampleCluster], style: PaletteStyle) -> TerminalPalettePair {
        TerminalPalettePair(
            dark: make(clusters, style: style, dark: true),
            light: make(clusters, style: style, dark: false))
    }
    private static func make(_ clusters: [SampleCluster], style: PaletteStyle, dark: Bool)
        -> TerminalPalette
    {
        let total = Double(clusters.reduce(0) { $0 + $1.count })
        let supported = clusters.filter { Double($0.count) / total >= 0.008 }
        let pool = supported.isEmpty ? clusters : supported
        // Blend in OKLab to retain the image's overall cast; shadows/highlights are selected separately.
        let mean = OKColor(
            l: clusters.reduce(0) { $0 + $1.lab.l * Double($1.count) / total },
            a: clusters.reduce(0) { $0 + $1.lab.a * Double($1.count) / total },
            b: clusters.reduce(0) { $0 + $1.lab.b * Double($1.count) / total })
        let sorted = pool.sorted { $0.lab.l < $1.lab.l }
        let tail = max(1, sorted.count / 4)
        let backdropPool = dark ? Array(sorted.prefix(tail)) : Array(sorted.suffix(tail))
        let backdrop = backdropPool.max { $0.count < $1.count }!.lab
        // Surface chroma: soft tracks Noctalia muted (HSL sat ≈ 0.08 → OKLab C ≈ 0.008).
        // Faithful keeps a light wallpaper tint but stays below the old 0.030 cap that read as neon paste.
        // Vivid allows more tint, still softer on light backgrounds than dark.
        let bgCap: Double
        let bgScale: Double
        switch style {
        case .soft:
            bgCap = dark ? 0.012 : 0.008
            bgScale = 0.30
        case .vivid:
            bgCap = dark ? 0.038 : 0.020
            bgScale = 0.80
        case .faithful, .aether:
            bgCap = dark ? 0.022 : 0.012
            bgScale = 0.45
        }
        let bgChroma = min(bgCap, backdrop.chroma * bgScale)
        let background = backdrop.at(dark ? 0.18 : 0.965, chroma: bgChroma).rgb
        let foreground = readable(
            mean.at(dark ? 0.91 : 0.25, chroma: min(mean.chroma, 0.018)).rgb,
            on: background, ratio: 7, dark: dark)
        // Preserve multiple hue families; popularity matters, but a secondary image color can survive.
        let colorful = pool.filter { $0.lab.chroma >= 0.025 }
        let candidates = colorful.isEmpty ? pool : colorful
        func score(_ c: SampleCluster) -> Double {
            pow(Double(c.count) / total, 0.45) * (0.025 + c.lab.chroma)
        }
        var chosen: [SampleCluster] = []
        for _ in 0..<min(6, candidates.count) {
            let remaining = candidates.filter { c in !chosen.contains(where: { $0.color == c.color }) }
            let next = remaining.max { x, y in
                func diversity(_ c: SampleCluster) -> Double {
                    if chosen.isEmpty { return score(c) }
                    let distance = chosen.map { prior -> Double in
                        let hue = hueDistance(c.lab.hue, prior.lab.hue) / 180
                        return hue * 0.8 + abs(c.lab.l - prior.lab.l) * 0.2
                    }.min()!
                    return score(c) * (0.05 + distance)
                }
                return diversity(x) < diversity(y)
            }!
            chosen.append(next)
        }
        let source = chosen[0].color
        // ANSI hue targets choose only among real image colors. Missing hue families reuse nearby ones.
        // Missing hue families intentionally trade ANSI hue semantics for wallpaper fidelity.
        let targets = [29.0, 142, 100, 264, 328, 195]
        var assigned: [SampleCluster] = []
        for hue in targets {
            let ranked = chosen.sorted { x, y in
                func cost(_ c: SampleCluster) -> Double {
                    hueDistance(c.lab.hue, hue) / 180
                        + (assigned.contains(where: { $0.color == c.color }) ? 0.14 : 0)
                }
                return cost(x) < cost(y)
            }
            assigned.append(ranked[0])
        }
        func accent(_ c: SampleCluster, bright: Bool = false) -> RGBColor {
            let lab = c.lab
            let factor: Double
            let chromaCap: Double
            switch style {
            case .soft:
                factor = 0.45
                chromaCap = 0.10
            case .vivid:
                factor = 1.35
                chromaCap = 0.23
            case .faithful, .aether:
                factor = 1.0
                chromaCap = 0.16
            }
            let chroma = min(chromaCap, lab.chroma * factor)
            let l = dark ? min(0.86, max(0.68, lab.l)) : min(0.52, max(0.36, lab.l))
            return readable(
                lab.at(l + (bright ? (dark ? 0.06 : -0.04) : 0), chroma: chroma).rgb,
                on: background, ratio: 4.5, dark: dark)
        }
        let cursor = accent(chosen[0])
        let black = backdrop.at(dark ? 0.23 : 0.30, chroma: bgChroma).rgb
        let white = mean.at(dark ? 0.86 : 0.87, chroma: min(mean.chroma, 0.015)).rgb
        let muted = readable(
            mean.at(dark ? 0.63 : 0.49, chroma: min(mean.chroma, 0.025)).rgb,
            on: background, ratio: 4.5, dark: dark)
        let selection = cursor.blended(with: background, amount: dark ? 0.72 : 0.84)
        return TerminalPalette(
            source: source, background: background, foreground: foreground,
            cursor: cursor, cursorText: background, selectionBackground: selection,
            selectionForeground: readable(foreground, on: selection, ratio: 4.5, dark: dark),
            normal: [black] + assigned.map { accent($0) } + [white],
            bright: [muted] + assigned.map { accent($0, bright: true) } + [foreground])
    }
    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 360 - d)
    }
}
