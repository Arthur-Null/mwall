import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MWall

@Test func legacySettingsKeepPreferencesWhenPaletteStyleIsAdded() throws {
    let data = Data(
        #"{"applyToAllScreens":false,"applyThemeAfterWallpaperChange":false,"reloadTerminalsAfterThemeChange":false,"launchAtLogin":true,"enabledThemeTargets":["neovim","pi"],"currentSource":"unsplash","unsplashAccessKey":"test-fixture","unsplashCacheLimitMB":1200}"#
            .utf8)
    let settings = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(settings.paletteStyle == .faithful)
    #expect(!settings.applyToAllScreens && !settings.applyThemeAfterWallpaperChange)
    #expect(!settings.reloadTerminalsAfterThemeChange && settings.launchAtLogin)
    #expect(settings.enabledThemeTargets == [.neovim, .pi])
    #expect(settings.currentSource == .unsplash && settings.unsplashAccessKey == "test-fixture")
    #expect(settings.unsplashCacheLimitMB == 1200)
    for style in PaletteStyle.allCases {
        var changed = settings
        changed.paletteStyle = style
        #expect(
            try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed)) == changed)
    }
    #expect(Set(PaletteStyle.allCases.map(\.rawValue)) == ["aether", "faithful", "soft", "vivid"])
    let unknown = try JSONDecoder().decode(
        AppSettings.self, from: Data(#"{"paletteStyle":"old","enabledThemeTargets":[]}"#.utf8))
    #expect(unknown.paletteStyle == .faithful && unknown.enabledThemeTargets.isEmpty)
}

@Test func wallpaperStylesAreDistinctAndReadable() throws {
    let file = try paletteFixture()
    defer { try? FileManager.default.removeItem(at: file) }
    var results: [TerminalPalettePair] = []
    for style in [PaletteStyle.faithful, .soft, .vivid] {
        let pair = try PaletteGenerator.generate(from: file, style: style)
        results.append(pair)
        for palette in [pair.dark, pair.light] {
            #expect(palette.normal.count == 8 && palette.bright.count == 8)
            #expect(contrast(palette.foreground, palette.background) >= 7)
            for color in Array(palette.normal[1...6]) + Array(palette.bright[1...6]) {
                #expect(contrast(color, palette.background) >= 4.5)
            }
        }
    }
    #expect(results[0] != results[1] && results[1] != results[2] && results[0] != results[2])
    #expect(try PaletteGenerator.generate(from: file) == results[0])
}

@Test func aetherEngineRunsForAnImageWithoutChangingRoles() throws {
    let file = try paletteFixture()
    defer { try? FileManager.default.removeItem(at: file) }
    let pair = try PaletteGenerator.generate(from: file, style: .aether)
    for palette in [pair.dark, pair.light] {
        #expect(palette.normal.count == 8 && palette.bright.count == 8)
        #expect(palette.background == palette.normal[0])
        #expect(palette.foreground == palette.normal[7])
        #expect(palette.cursor == palette.foreground)
        #expect(palette.accent == palette.normal[4])
        #expect(palette.selectionBackground == palette.foreground)
        #expect(palette.selectionForeground == palette.background)
    }
    #expect(pair.dark.background != pair.light.background)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mwall-aether-roles-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try AgentThemeWriter.writePi(pair, file, directory: root.appendingPathComponent("pi"))
    _ = try AgentThemeWriter.writeCodexCLI(pair, file, directory: root.appendingPathComponent("codex"))
    let pi = try #require(
        JSONSerialization.jsonObject(
            with: Data(
                contentsOf:
                    root.appendingPathComponent("pi/themes/mwall-dark.json"))) as? [String: Any])
    let colors = try #require(pi["colors"] as? [String: String])
    #expect(colors["accent"] == pair.dark.normal[4].hex)
    let codex = try #require(
        PropertyListSerialization.propertyList(
            from: Data(
                contentsOf:
                    root.appendingPathComponent("codex/themes/mwall-dark.tmTheme")), options: [], format: nil)
            as? [String: Any])
    let rows = try #require(codex["settings"] as? [[String: Any]])
    let base = try #require(rows.first?["settings"] as? [String: String])
    #expect(base["caret"] == pair.dark.foreground.hex)

}

@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MWALL_PALETTE_REFERENCE"] != nil,
        "Set reference JSON and cache paths to compare with the reviewed eight-wallpaper preview"))
func productionStylesMatchReviewedPreview() throws {
    struct Variant: Decodable {
        let id: String
        var palettes: TerminalPalettePair
    }
    struct Image: Decodable {
        let file: String
        let variants: [Variant]
    }
    let env = ProcessInfo.processInfo.environment
    let reference = try #require(env["MWALL_PALETTE_REFERENCE"])
    let cache = URL(fileURLWithPath: try #require(env["MWALL_PALETTE_CACHE"]))
    let images = try JSONDecoder().decode(
        [Image].self, from: Data(contentsOf: URL(fileURLWithPath: reference)))
    #expect(images.count == 8)
    for image in images {
        for style in PaletteStyle.allCases {
            var expected = try #require(image.variants.first { $0.id == style.rawValue })
            let actual = try PaletteGenerator.generate(
                from: cache.appendingPathComponent("Full").appendingPathComponent(image.file), style: style)
            if style == .aether {
                expected.palettes.dark.accentOverride = expected.palettes.dark.normal[4]
                expected.palettes.light.accentOverride = expected.palettes.light.normal[4]
            }
            #expect(actual == expected.palettes, Comment(rawValue: "\(image.file) / \(style.rawValue)"))
        }
    }
}

@Test func paletteServiceSeparatesStylesAndInvalidatesChangedFiles() async throws {
    let file = try paletteFixture()
    defer { try? FileManager.default.removeItem(at: file) }
    let service = PaletteService()
    let soft = try await service.generate(from: file, style: .soft)
    let vivid = try await service.generate(from: file, style: .vivid)
    #expect(soft != vivid)
    #expect(try await service.generate(from: file, style: .soft) == soft)
    let replacement = try paletteFixture(invert: true)
    defer { try? FileManager.default.removeItem(at: replacement) }
    try Data(contentsOf: replacement).write(to: file, options: .atomic)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: file.path)
    #expect(try await service.generate(from: file, style: .soft) != soft)
}

private func paletteFixture(invert: Bool = false) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "mwall palette \(UUID().uuidString).png")
    let colors =
        invert ? [0x4f63c5, 0xc252a0, 0x49b38e, 0x17304b] : [0xa3442a, 0x79ab68, 0x2d88b1, 0xebc274]
    var bytes = [UInt8](repeating: 255, count: 64 * 48 * 4)
    for y in 0..<48 {
        for x in 0..<64 {
            let value = colors[x / 16]
            let offset = (y * 64 + x) * 4
            bytes[offset] = UInt8((value >> 16) & 255)
            bytes[offset + 1] = UInt8((value >> 8) & 255)
            bytes[offset + 2] = UInt8(value & 255)
        }
    }
    try bytes.withUnsafeMutableBytes { raw in
        let context = try #require(
            CGContext(
                data: raw.baseAddress, width: 64, height: 48, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
    return url
}
