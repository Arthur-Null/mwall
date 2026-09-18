import AppKit
import Foundation
import ImageIO

struct RGBColor: Codable, Hashable, Sendable {
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

struct TerminalPalette: Codable, Equatable, Sendable {
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

struct TerminalPalettePair: Codable, Equatable, Sendable {
    var dark: TerminalPalette
    var light: TerminalPalette

    var current: TerminalPalette {
        systemPrefersDarkAppearance() ? dark : light
    }
}

enum PaletteGenerator {
    static func generate(from imageURL: URL, style: PaletteStyle = .faithful) throws
        -> TerminalPalettePair
    {
        if style == .aether { return try AetherPalette.generate(from: imageURL) }
        return try PerceptualPalette.pair(PerceptualPalette.clusters(from: imageURL), style: style)
    }
}

private func systemPrefersDarkAppearance() -> Bool {
    if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
        return style.caseInsensitiveCompare("Dark") == .orderedSame
    }
    return false
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
