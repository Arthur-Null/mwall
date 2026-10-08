import Foundation
import Testing
@testable import MWall

@Test func codexAppTargetIsOptInAndRoundTrips() throws {
    #expect(ThemeTarget.allCases.contains(.codexApp))
    #expect(ThemeTarget.supported.contains(.codexApp))
    #expect(!ThemeTarget.defaultEnabled.contains(.codexApp))
    #expect(!AppSettings().enabledThemeTargets.contains(.codexApp))
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"enabledThemeTargets":["codex-app","pi"]}"#.utf8))
    #expect(settings.enabledThemeTargets == [.codexApp, .pi])
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
}

@Test func codexAppEditsPreservePreferencesAndSkipIdenticalThemes() throws {
    let desired: [String: [String: Any]] = ["appearanceDarkChromeTheme": [
        "accent": "#abcdef", "surface": "#123456", "ink": "#fedcba",
        "semanticColors": ["diffAdded": "#112233", "diffRemoved": "#445566", "skill": "#778899"]
    ]]
    let before: [String: Any] = [
        "appearanceDarkChromeTheme": [
            "contrast": 73, "opaqueWindows": true,
            "fonts": ["ui": "Inter", "code": "Menlo", "content": "Georgia"],
            "semanticColors": ["futureRole": "#000000"], "futureOption": "keep"
        ],
        "appearanceTheme": "light", "appearanceDarkCodeThemeId": "dracula", "other": true
    ]
    let edits = CodexAppThemeWriter.configurationEdits(themes: desired, desktop: before)
    let edit = try #require(edits.first)
    #expect(edits.count == 1)
    #expect(edit["keyPath"] as? String == "desktop.appearanceDarkChromeTheme")
    let theme = try #require(edit["value"] as? [String: Any])
    #expect(theme["contrast"] as? Int == 73)
    #expect(theme["opaqueWindows"] as? Bool == true)
    #expect((theme["fonts"] as? [String: String])?["content"] == "Georgia")
    #expect(theme["futureOption"] as? String == "keep")
    #expect((theme["semanticColors"] as? [String: String])?["futureRole"] == "#000000")
    #expect((theme["semanticColors"] as? [String: String])?["diffAdded"] == "#112233")
    var after = before
    after["appearanceDarkChromeTheme"] = theme
    #expect(CodexAppThemeWriter.configurationEdits(themes: desired, desktop: after).isEmpty)
    let first = try #require(CodexAppThemeWriter.configurationEdits(themes: desired, desktop: [:]).first?["value"] as? [String: Any])
    #expect(first["contrast"] as? Int == 45)
    #expect(first["opaqueWindows"] as? Bool == false)
    #expect((first["fonts"] as? [String: String])?.isEmpty == true)
}

@Test func codexConfigClientRejectsMalformedOutputAndBoundsTimeout() throws {
    let root = try temporaryCodexDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let malformed = try fixtureCLI(in: root, body: "read -r request\nprintf 'invalid json\\n'\n")
    let client = try CodexConfigClient(executableURL: malformed, directory: root, timeout: 1)
    defer { client.close() }
    #expect(throws: CodexAppSyncError.protocolFailure) {
        _ = try client.request("initialize", params: [:])
    }

    let silent = try fixtureCLI(in: root, body: "read -r request\nwhile read -r request; do :; done\n")
    let stalled = try CodexConfigClient(executableURL: silent, directory: root, timeout: 0.2)
    defer { stalled.close() }
    let start = Date()
    #expect(throws: CodexAppSyncError.timeout) {
        _ = try stalled.request("initialize", params: [:])
    }
    #expect(Date().timeIntervalSince(start) < 2)

    // Timeout also bounds a pipe write when an unresponsive process fills stdin.
    let neverReads = try fixtureCLI(in: root, body: "while :; do :; done\n")
    let blocked = try CodexConfigClient(executableURL: neverReads, directory: root, timeout: 0.2)
    defer { blocked.close() }
    #expect(throws: CodexAppSyncError.timeout) {
        _ = try blocked.request("initialize", params: ["large": String(repeating: "x", count: 1_000_000)])
    }

    let rejected = try fixtureCLI(in: root, body: #"read -r request; printf '%s\n' '{"id":1,"error":{"code":-32000,"message":"private diagnostic"}}'"#)
    let rejecting = try CodexConfigClient(executableURL: rejected, directory: root, timeout: 1)
    defer { rejecting.close() }
    #expect(throws: CodexAppSyncError.rejected) {
        _ = try rejecting.request("initialize", params: [:])
    }
    #expect(CodexAppSyncError.rejected.localizedDescription.contains("private diagnostic") == false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MWALL_CODEX_CLI"] != nil,
               "Set MWALL_CODEX_CLI to an installed CLI for isolated native TOML integration"))
func codexAppSynchronizationPreservesConfigAndRejectsConflicts() async throws {
    let root = try temporaryCodexDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MWALL_CODEX_CLI"]))
    let file = root.appendingPathComponent("config.toml")
    let original = """
    # MWall must preserve this comment
    model = "gpt-5.4"
    [tui]
    theme = "keep-cli-theme"
    [desktop]
    appearanceTheme = "system"
    appearanceDarkCodeThemeId = "dracula"
    appearanceLightCodeThemeId = "github-light"
    [desktop.appearanceDarkChromeTheme]
    contrast = 71
    opaqueWindows = true
    [desktop.appearanceDarkChromeTheme.fonts]
    ui = "Inter"
    code = "Menlo"
    content = "Georgia"
    [desktop.appearanceDarkChromeTheme.semanticColors]
    futureRole = "#123456"
    [projects."/tmp/user project"]
    trust_level = "trusted"

    """
    try Data(original.utf8).write(to: file)
    let first = codexAppPalettes(accent: RGBColor(r: 34, g: 136, b: 187))
    let files = try await CodexAppThemeWriter.write(first, directory: root, executableURL: executable)
    #expect(files == [file])
    let written = try String(contentsOf: file, encoding: .utf8)
    #expect(written.contains("# MWall must preserve this comment"))
    #expect(written.contains("trust_level = \"trusted\""))
    let sentinel = Date(timeIntervalSince1970: 1_000)
    try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: file.path)
    _ = try await CodexAppThemeWriter.write(first, directory: root, executableURL: executable)
    #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == sentinel)
    let second = codexAppPalettes(accent: RGBColor(r: 187, g: 68, b: 136))
    _ = try await CodexAppThemeWriter.write(second, directory: root, executableURL: executable)

    let client = try CodexConfigClient(executableURL: executable, directory: root)
    defer { client.close() }
    _ = try client.request("initialize", params: ["clientInfo": ["name": "mwall-test", "version": "1.0.0"]])
    try client.notify("initialized")
    let read = try client.request("config/read", params: ["includeLayers": true])
    let config = try #require(read["config"] as? [String: Any])
    let desktop = try #require(config["desktop"] as? [String: Any])
    #expect(config["model"] as? String == "gpt-5.4")
    #expect((config["tui"] as? [String: Any])?["theme"] as? String == "keep-cli-theme")
    #expect(desktop["appearanceTheme"] as? String == "system")
    #expect(desktop["appearanceDarkCodeThemeId"] as? String == "dracula")
    #expect(desktop["appearanceLightCodeThemeId"] as? String == "github-light")
    for (key, expected) in [("appearanceDarkChromeTheme", second.dark), ("appearanceLightChromeTheme", second.light)] {
        let theme = try #require(desktop[key] as? [String: Any])
        #expect(theme["accent"] as? String == expected.accent.hex.lowercased())
        #expect(theme["surface"] as? String == expected.background.hex.lowercased())
        #expect(theme["ink"] as? String == expected.foreground.hex.lowercased())
        #expect(theme["accentSource"] as? String == "custom")
        let semantic = try #require(theme["semanticColors"] as? [String: String])
        #expect(semantic["diffAdded"] == expected.normal[2].hex.lowercased())
        #expect(semantic["diffRemoved"] == expected.normal[1].hex.lowercased())
        #expect(semantic["skill"] == expected.normal[5].hex.lowercased())
    }
    let dark = try #require(desktop["appearanceDarkChromeTheme"] as? [String: Any])
    #expect(dark["contrast"] as? Int == 71)
    #expect(dark["opaqueWindows"] as? Bool == true)
    #expect((dark["fonts"] as? [String: String]) == ["ui": "Inter", "code": "Menlo", "content": "Georgia"])
    #expect((dark["semanticColors"] as? [String: String])?["futureRole"] == "#123456")
    let light = try #require(desktop["appearanceLightChromeTheme"] as? [String: Any])
    #expect(light["contrast"] as? Int == 45)
    #expect(light["opaqueWindows"] as? Bool == false)
    #expect((light["fonts"] as? [String: String])?.isEmpty == true)

    let layers = try #require(read["layers"] as? [[String: Any]])
    let layer = try #require(layers.first { ($0["name"] as? [String: Any])?["type"] as? String == "user" })
    let version = try #require(layer["version"] as? String)
    let concurrentText = try String(contentsOf: file, encoding: .utf8)
        .replacingOccurrences(of: "appearanceTheme = \"system\"", with: "appearanceTheme = \"light\"")
    let concurrent = Data((concurrentText + "\n# concurrent user edit\n").utf8)
    try concurrent.write(to: file)
    #expect(throws: CodexAppSyncError.rejected) {
        _ = try client.request("config/batchWrite", params: [
            "edits": [["keyPath": "desktop.appearanceTheme", "mergeStrategy": "replace", "value": "dark"]],
            "expectedVersion": version, "filePath": file.path
        ])
    }
    #expect(try Data(contentsOf: file) == concurrent)

    // A first install must create valid theme tables without requiring an existing config file.
    let empty = root.appendingPathComponent("empty home")
    _ = try await CodexAppThemeWriter.write(first, directory: empty, executableURL: executable)
    #expect(FileManager.default.fileExists(atPath: empty.appendingPathComponent("config.toml").path))

    // Invalid user configuration must remain byte-for-byte intact.
    let invalid = root.appendingPathComponent("invalid home")
    try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
    let invalidFile = invalid.appendingPathComponent("config.toml")
    let invalidData = Data("[desktop\nappearanceTheme = \"system\"\n".utf8)
    try invalidData.write(to: invalidFile)
    await #expect(throws: (any Error).self) {
        _ = try await CodexAppThemeWriter.write(first, directory: invalid, executableURL: executable)
    }
    #expect(try Data(contentsOf: invalidFile) == invalidData)
}

private func temporaryCodexDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MWall Codex \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func fixtureCLI(in root: URL, body: String) throws -> URL {
    let file = root.appendingPathComponent("fake-codex-\(UUID().uuidString)")
    try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    return file
}

private func codexAppPalettes(accent: RGBColor) -> TerminalPalettePair {
    func palette(background: RGBColor, foreground: RGBColor) -> TerminalPalette {
        let normal = [background, RGBColor(r: 210, g: 70, b: 80), RGBColor(r: 80, g: 170, b: 90),
                      RGBColor(r: 190, g: 150, b: 40), accent, RGBColor(r: 165, g: 90, b: 180),
                      RGBColor(r: 50, g: 160, b: 180), foreground]
        return TerminalPalette(source: accent, background: background, foreground: foreground,
                               cursor: accent, cursorText: background, selectionBackground: accent,
                               selectionForeground: foreground, normal: normal, bright: normal)
    }
    return TerminalPalettePair(
        dark: palette(background: RGBColor(r: 20, g: 25, b: 30), foreground: RGBColor(r: 230, g: 235, b: 240)),
        light: palette(background: RGBColor(r: 240, g: 245, b: 250), foreground: RGBColor(r: 30, g: 35, b: 40)))
}
