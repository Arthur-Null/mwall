// Imports original Aether CLI results without changing any RGB values.
import CryptoKit
import Foundation

struct AetherMode: Decodable {
    let colors: [String]
    let variables: [String: String]

    func color(_ name: String) throws -> RGBColor {
        guard let value = variables[name] else { throw invalid("Missing Aether role: \(name)") }
        return try rgb(value)
    }

    func palette() throws -> TerminalPalette {
        guard colors.count == 16 else { throw invalid("Expected 16 Aether ANSI colors") }
        let ansi = try colors.map(rgb)
        for index in ansi.indices {
            guard try color("color\(index)") == ansi[index] else {
                throw invalid("Aether ANSI slot \(index) differs from template variables")
            }
        }
        return TerminalPalette(
            source: try color("accent"), background: try color("background"),
            foreground: try color("foreground"), cursor: try color("cursor"),
            cursorText: try color("background"),
            selectionBackground: try color("selection_background"),
            selectionForeground: try color("selection_foreground"),
            normal: Array(ansi.prefix(8)), bright: Array(ansi.suffix(8))
        )
    }
}

struct AetherRecord: Decodable {
    let file: String
    let sha256: String
    let palettes: [String: AetherMode]
}
struct AetherProvenance: Encodable {
    let repository: String
    let commit: String
    let mode: String
    let adjustments: String
    let sha256: String
}
struct AetherReference: Decodable {
    let schema: Int
    let engine: String
    let repository: String
    let commit: String
    let mode: String
    let adjustments: String
    let images: [String: AetherRecord]

    func variant(id: String, file: URL) throws -> Variant {
        guard schema == 1, engine == "Aether", mode == "normal", adjustments == "none",
              repository == "https://github.com/omacom/aether",
              commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let record = images[id], record.file == file.lastPathComponent,
              let dark = record.palettes["dark"], let light = record.palettes["light"] else {
            throw invalid("Invalid or incomplete Aether reference for \(id)")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        guard digest == record.sha256 else { throw invalid("Aether input SHA-256 mismatch for \(id)") }
        return Variant(
            id: "aether", palettes: TerminalPalettePair(dark: try dark.palette(), light: try light.palette()),
            accents: ["dark": try dark.color("accent"), "light": try light.color("accent")],
            provenance: AetherProvenance(repository: repository, commit: commit, mode: mode,
                                         adjustments: adjustments, sha256: digest)
        )
    }
}
private func invalid(_ message: String) -> NSError {
    NSError(domain: "AetherReference", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
private func rgb(_ hex: String) throws -> RGBColor {
    guard hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
          let value = UInt32(hex.dropFirst(), radix: 16) else { throw invalid("Invalid Aether color: \(hex)") }
    return RGBColor(r: Int(value >> 16), g: Int((value >> 8) & 255), b: Int(value & 255))
}

