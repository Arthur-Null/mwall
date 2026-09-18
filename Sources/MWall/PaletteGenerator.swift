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

    func blended(with other: RGBColor, amount: Double) -> RGBColor {
        let t = min(max(amount, 0.0), 1.0)
        return RGBColor(
            r: Int((Double(r) * (1.0 - t) + Double(other.r) * t).rounded()),
            g: Int((Double(g) * (1.0 - t) + Double(other.g) * t).rounded()),
            b: Int((Double(b) * (1.0 - t) + Double(other.b) * t).rounded())
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
    var accentOverride: RGBColor? = nil

    var accent: RGBColor { accentOverride ?? cursor }
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
