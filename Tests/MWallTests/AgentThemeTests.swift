import Foundation
@testable import MWall
import Testing

@Test func agentThemeTargetsPreserveExistingSelections() throws {
    #expect(ThemeTarget.supported.contains(.pi))
    #expect(ThemeTarget.supported.contains(.codexCLI))
    #expect(ThemeTarget.defaultEnabled.contains(.pi))
    #expect(ThemeTarget.defaultEnabled.contains(.codexCLI))
    let saved = Data(#"["kitty","neovim"]"#.utf8)
    #expect(try JSONDecoder().decode(Set<ThemeTarget>.self, from: saved) == [.kitty, .neovim])
    let encoded = try JSONEncoder().encode(Set<ThemeTarget>([.pi, .codexCLI]))
    #expect(try JSONDecoder().decode(Set<ThemeTarget>.self, from: encoded) == [.pi, .codexCLI])
}

@Test func agentThemeDirectoriesRespectEnvironment() {
    let home = URL(fileURLWithPath: "/tmp/mwall test home")
    for (variable, fallback) in [("CODEX_HOME", ".codex"), ("PI_CODING_AGENT_DIR", ".pi/agent")] {
        #expect(AgentThemeWriter.configDirectory(
            variable: variable, fallback: fallback, environment: [:], homeDirectory: home
        ) == home.appendingPathComponent(fallback))
        #expect(AgentThemeWriter.configDirectory(
            variable: variable, fallback: fallback, environment: [variable: "  "], homeDirectory: home
        ) == home.appendingPathComponent(fallback))
        #expect(AgentThemeWriter.configDirectory(
            variable: variable, fallback: fallback, environment: [variable: "~/custom agent"], homeDirectory: home
        ).path == "/tmp/mwall test home/custom agent")
        #expect(AgentThemeWriter.configDirectory(
            variable: variable, fallback: fallback, environment: [variable: "/tmp/custom agent"], homeDirectory: home
        ).path == "/tmp/custom agent")
    }
}

@Test func generatedAgentThemesMatchPalettesAndPreserveUserConfig() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MWall-agent-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let palettes = agentPalettes(accent: RGBColor(r: 34, g: 136, b: 187))
    let wallpaper = URL(fileURLWithPath: "/tmp/sky & sea <blue> \"quoted\".jpg")
    let pi = root.appendingPathComponent("pi")
    let codex = root.appendingPathComponent("codex")
    for directory in [pi, codex] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let piSettings = pi.appendingPathComponent("settings.json")
    let codexSettings = codex.appendingPathComponent("config.toml")
    try Data(#"{"theme":"other","defaultModel":"keep"}"#.utf8).write(to: piSettings)
    try Data("[tui]\ntheme = \"other\"\n".utf8).write(to: codexSettings)
    let beforePi = try Data(contentsOf: piSettings)
    let beforeCodex = try Data(contentsOf: codexSettings)
    let piFiles = try AgentThemeWriter.writePi(palettes, wallpaper, directory: pi)
    let codexFiles = try AgentThemeWriter.writeCodexCLI(palettes, wallpaper, directory: codex)
    #expect(Set(piFiles.map(\.lastPathComponent)) == ["mwall.json", "mwall-dark.json", "mwall-light.json"])
    #expect(Set(codexFiles.map(\.lastPathComponent)) == ["mwall.tmTheme", "mwall-dark.tmTheme", "mwall-light.tmTheme"])
    for (name, expected) in [("mwall-dark", palettes.dark), ("mwall-light", palettes.light), ("mwall", palettes.current)] {
        let json = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: pi.appendingPathComponent("themes/\(name).json"))
        ) as? [String: Any])
        #expect(json["name"] as? String == name)
        let colors = try #require(json["colors"] as? [String: String])
        #expect(colors.count == 56)
        #expect(colors["accent"] == expected.cursor.hex)
        #expect(colors["text"] == expected.foreground.hex)
        #expect(colors["searchMatchText"] == expected.selectionForeground.hex)
        #expect(colors["toolDiffAdded"] == expected.normal[2].hex)
        #expect(colors["syntaxKeyword"] == expected.normal[5].hex)
        #expect(colors.values.allSatisfy { $0.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil })
        let plist = try #require(PropertyListSerialization.propertyList(
            from: Data(contentsOf: codex.appendingPathComponent("themes/\(name).tmTheme")), options: [], format: nil
        ) as? [String: Any])
        #expect(plist["name"] as? String == name)
        #expect((plist["comment"] as? String)?.contains(wallpaper.path) == true)
        let settings = try #require(plist["settings"] as? [[String: Any]])
        let base = try #require(settings.first?["settings"] as? [String: String])
        #expect(base["background"] == expected.background.hex)
        #expect(base["foreground"] == expected.foreground.hex)
        let strings = try #require(settings.first { $0["scope"] as? String == "string" })
        #expect((strings["settings"] as? [String: String])?["foreground"] == expected.normal[2].hex)
    }
    #expect(try Data(contentsOf: piSettings) == beforePi)
    #expect(try Data(contentsOf: codexSettings) == beforeCodex)

    // Byte-identical regeneration must leave the file untouched, not merely rewrite identical data.
    let sentinel = Date(timeIntervalSince1970: 1_000)
    for file in piFiles + codexFiles {
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: file.path)
    }
    _ = try AgentThemeWriter.writePi(palettes, wallpaper, directory: pi)
    _ = try AgentThemeWriter.writeCodexCLI(palettes, wallpaper, directory: codex)
    for file in piFiles + codexFiles {
        #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == sentinel)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PI_PACKAGE_DIR"] != nil,
               "Set PI_PACKAGE_DIR to an installed pi-coding-agent package for live reload validation"))
func piReloadsGeneratedAgentThemes() throws {
    let environment = ProcessInfo.processInfo.environment
    let exportedRoot = environment["MWALL_THEME_FIXTURE_DIR"]
    let root = exportedRoot.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("MWall-pi-live-\(UUID().uuidString)")
    defer {
        if exportedRoot == nil { try? FileManager.default.removeItem(at: root) }
    }
    let wallpaper = URL(fileURLWithPath: "/tmp/mwall-fixture.jpg")
    for (version, accent) in [("first", RGBColor(r: 34, g: 136, b: 187)),
                              ("second", RGBColor(r: 187, g: 68, b: 136))] {
        let palettes = agentPalettes(accent: accent)
        _ = try AgentThemeWriter.writePi(palettes, wallpaper, directory: root.appendingPathComponent("\(version)/pi"))
        _ = try AgentThemeWriter.writeCodexCLI(palettes, wallpaper, directory: root.appendingPathComponent("\(version)/codex"))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.currentDirectoryURL = root
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("pi_theme_reload.mjs")
    process.arguments = ["node", script.path, root.path, try #require(environment["PI_PACKAGE_DIR"])]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: log))
    #expect(log.contains("Pi generated theme reload PASS"), Comment(rawValue: log))
}

private func agentPalettes(accent: RGBColor) -> TerminalPalettePair {
    func palette(background: RGBColor, foreground: RGBColor) -> TerminalPalette {
        let normal = [
            background, RGBColor(r: 210, g: 70, b: 80), RGBColor(r: 80, g: 170, b: 90),
            RGBColor(r: 190, g: 150, b: 40), accent, RGBColor(r: 165, g: 90, b: 180),
            RGBColor(r: 50, g: 160, b: 180), foreground
        ]
        return TerminalPalette(
            source: accent, background: background, foreground: foreground, cursor: accent,
            cursorText: background, selectionBackground: accent, selectionForeground: foreground,
            normal: normal, bright: normal
        )
    }
    return TerminalPalettePair(
        dark: palette(background: RGBColor(r: 20, g: 25, b: 30), foreground: RGBColor(r: 230, g: 235, b: 240)),
        light: palette(background: RGBColor(r: 240, g: 245, b: 250), foreground: RGBColor(r: 30, g: 35, b: 40))
    )
}
