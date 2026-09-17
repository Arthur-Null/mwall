import Foundation
@testable import MWall
import Testing

private let neovimExecutable: URL? = {
    let candidates = [ProcessInfo.processInfo.environment["NVIM_BIN"]]
        + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/nvim" }
        + ["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim", "/usr/bin/nvim"]
    return candidates.compactMap { $0 }.first {
        FileManager.default.isExecutableFile(atPath: $0)
    }.map { URL(fileURLWithPath: $0) }
}()

@Test(.enabled(if: neovimExecutable != nil, "Install Neovim or set NVIM_BIN for the live reload integration test"))
func neovimReloadsGeneratedThemesInOneProcess() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWall Neovim \(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let wallpaper = URL(fileURLWithPath: "/tmp/wallpaper with spaces.jpg")
    for (name, accent) in [("first", RGBColor(r: 60, g: 130, b: 190)),
                           ("second", RGBColor(r: 210, g: 90, b: 150))] {
        let palettes = TerminalPalettePair(
            dark: testPalette(background: RGBColor(r: 20, g: 25, b: 30), accent: accent),
            light: testPalette(background: RGBColor(r: 240, g: 245, b: 250), accent: accent)
        )
        let files = try ThemeManager.writeNeovim(
            palettes, wallpaper, configDirectory: root.appendingPathComponent(name)
        )
        #expect(files.count == 4)
    }

    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("neovim_reload.lua")
    let process = Process()
    process.executableURL = neovimExecutable
    process.arguments = ["--headless", "-u", "NONE", "-i", "NONE", "-l", script.path]
    var environment = ProcessInfo.processInfo.environment
    environment["MWALL_NVIM_TEST_DIR"] = root.path
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let log = String(decoding: data, as: UTF8.self)
    #expect(process.terminationStatus == 0, Comment(rawValue: log))
    #expect(log.contains("MWall live reload PASS"), Comment(rawValue: log))
}

private func testPalette(background: RGBColor, accent: RGBColor) -> TerminalPalette {
    let foreground = background.luminance < 0.5
        ? RGBColor(r: 230, g: 235, b: 240) : RGBColor(r: 30, g: 35, b: 40)
    return TerminalPalette(
        source: accent, background: background, foreground: foreground,
        cursor: accent, cursorText: background, selectionBackground: accent,
        selectionForeground: foreground, normal: Array(repeating: accent, count: 8),
        bright: Array(repeating: accent, count: 8)
    )
}
