import Foundation

struct ThemeApplyReport {
    var writtenFiles: [URL]
    var reloadAttempts: [String]
}

enum ThemeManager {
    static func apply(
        palette: TerminalPalette,
        wallpaperURL: URL,
        targets: Set<ThemeTarget>,
        reloadTerminals: Bool
    ) throws -> ThemeApplyReport {
        var written: [URL] = []
        for target in targets.sorted(by: { $0.rawValue < $1.rawValue }) {
            let files = try writer(for: target)(palette, wallpaperURL)
            written.append(contentsOf: files)
        }
        let reloads = reloadTerminals ? TerminalReloader.reload(targets: targets) : []
        return ThemeApplyReport(writtenFiles: written, reloadAttempts: reloads)
    }

    private static func writer(for target: ThemeTarget) -> (TerminalPalette, URL) throws -> [URL] {
        switch target {
        case .kitty: writeKitty
        case .alacritty: writeAlacritty
        case .wezterm: writeWezTerm
        case .ghostty: writeGhostty
        case .iterm2: writeIterm2
        case .terminal: writeTerminalScript
        }
    }

    private static func writeKitty(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = home(".config/kitty/themes/mwall.conf")
        let lines = header(wallpaperURL) + [
            "foreground \(palette.foreground.hex)",
            "background \(palette.background.hex)",
            "cursor \(palette.cursor.hex)",
            "cursor_text_color \(palette.cursorText.hex)",
            "selection_foreground \(palette.selectionForeground.hex)",
            "selection_background \(palette.selectionBackground.hex)"
        ] + ansiLines(prefix: "color", palette: palette)
        try write(lines.joined(separator: "\n") + "\n", to: url)
        return [url]
    }

    private static func writeAlacritty(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = home(".config/alacritty/themes/mwall.toml")
        var lines = header(wallpaperURL)
        lines += [
            "[colors.primary]",
            "background = '\(palette.background.hex)'",
            "foreground = '\(palette.foreground.hex)'",
            "",
            "[colors.cursor]",
            "text = '\(palette.cursorText.hex)'",
            "cursor = '\(palette.cursor.hex)'",
            "",
            "[colors.selection]",
            "text = '\(palette.selectionForeground.hex)'",
            "background = '\(palette.selectionBackground.hex)'",
            "",
            "[colors.normal]"
        ]
        lines += namedAnsi(palette.normal).map { "\($0.key) = '\($0.value.hex)'" }
        lines += ["", "[colors.bright]"]
        lines += namedAnsi(palette.bright).map { "\($0.key) = '\($0.value.hex)'" }
        try write(lines.joined(separator: "\n") + "\n", to: url)
        return [url]
    }

    private static func writeWezTerm(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = home(".config/wezterm/colors/mwall.toml")
        let lines = header(wallpaperURL) + [
            "[colors]",
            "foreground = '\(palette.foreground.hex)'",
            "background = '\(palette.background.hex)'",
            "cursor_bg = '\(palette.cursor.hex)'",
            "cursor_fg = '\(palette.cursorText.hex)'",
            "selection_fg = '\(palette.selectionForeground.hex)'",
            "selection_bg = '\(palette.selectionBackground.hex)'",
            "ansi = \(tomlArray(palette.normal))",
            "brights = \(tomlArray(palette.bright))"
        ]
        try write(lines.joined(separator: "\n") + "\n", to: url)
        return [url]
    }

    private static func writeGhostty(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = home(".config/ghostty/themes/mwall")
        var lines = header(wallpaperURL)
        lines += [
            "background = \(palette.background.hex)",
            "foreground = \(palette.foreground.hex)",
            "cursor-color = \(palette.cursor.hex)",
            "cursor-text = \(palette.cursorText.hex)",
            "selection-background = \(palette.selectionBackground.hex)",
            "selection-foreground = \(palette.selectionForeground.hex)"
        ]
        for (index, color) in (palette.normal + palette.bright).enumerated() {
            lines.append("palette = \(index)=\(color.hex)")
        }
        try write(lines.joined(separator: "\n") + "\n", to: url)
        return [url]
    }

    private static func writeIterm2(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = StorePaths.appSupport.appendingPathComponent("MWall.itermcolors")
        let colors = [
            ("Background Color", palette.background),
            ("Foreground Color", palette.foreground),
            ("Cursor Color", palette.cursor),
            ("Cursor Text Color", palette.cursorText),
            ("Selection Color", palette.selectionBackground),
            ("Selected Text Color", palette.selectionForeground)
        ] + (0..<8).map { ("Ansi \($0) Color", palette.normal[$0]) }
          + (0..<8).map { ("Ansi \($0 + 8) Color", palette.bright[$0]) }

        var plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>

        """
        for (name, color) in colors {
            plist += colorDict(name: name, color: color)
        }
        plist += """
        </dict>
        </plist>
        """
        try write(plist, to: url)
        return [url]
    }

    private static func writeTerminalScript(_ palette: TerminalPalette, _ wallpaperURL: URL) throws -> [URL] {
        let url = StorePaths.appSupport.appendingPathComponent("Apply-MWall-Terminal.applescript")
        let script = """
        -- Generated by MWall from \(wallpaperURL.path)
        -- Run this script manually if you want to update the front Terminal.app tab.
        tell application "Terminal"
            if not (exists window 1) then reopen
            set background color of selected tab of front window to {\(appleRGB(palette.background))}
            set normal text color of selected tab of front window to {\(appleRGB(palette.foreground))}
            set cursor color of selected tab of front window to {\(appleRGB(palette.cursor))}
        end tell
        """
        try write(script, to: url)
        return [url]
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func home(_ relativePath: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativePath)
    }

    private static func header(_ wallpaperURL: URL) -> [String] {
        [
            "# Generated by MWall",
            "# Wallpaper: \(wallpaperURL.path)",
            "# Include/import this file from your terminal config if it is not loaded automatically.",
            ""
        ]
    }

    private static func ansiLines(prefix: String, palette: TerminalPalette) -> [String] {
        (palette.normal + palette.bright).enumerated().map { "\(prefix)\($0.offset) \($0.element.hex)" }
    }

    private static func namedAnsi(_ colors: [RGBColor]) -> [(key: String, value: RGBColor)] {
        zip(["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"], colors).map { ($0, $1) }
    }

    private static func tomlArray(_ colors: [RGBColor]) -> String {
        "[" + colors.map { "'\($0.hex)'" }.joined(separator: ", ") + "]"
    }

    private static func colorDict(name: String, color: RGBColor) -> String {
        let (r, g, b) = color.components01
        return """
            <key>\(name)</key>
            <dict>
                <key>Color Space</key>
                <string>sRGB</string>
                <key>Red Component</key>
                <real>\(String(format: "%.6f", r))</real>
                <key>Green Component</key>
                <real>\(String(format: "%.6f", g))</real>
                <key>Blue Component</key>
                <real>\(String(format: "%.6f", b))</real>
                <key>Alpha Component</key>
                <real>1</real>
            </dict>

        """
    }

    private static func appleRGB(_ color: RGBColor) -> String {
        "\(color.r * 257), \(color.g * 257), \(color.b * 257)"
    }
}
