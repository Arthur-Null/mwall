import Foundation

struct ThemeApplyReport {
    var writtenFiles: [URL]
    var reloadAttempts: [String]
}

enum ThemeManager {
    static func apply(
        palettes: TerminalPalettePair,
        wallpaperURL: URL,
        targets: Set<ThemeTarget>,
        reloadTerminals: Bool
    ) throws -> ThemeApplyReport {
        var written: [URL] = []
        for target in targets.sorted(by: { $0.rawValue < $1.rawValue }) {
            let files = try writer(for: target)(palettes, wallpaperURL)
            written.append(contentsOf: files)
        }
        let reloads = reloadTerminals ? TerminalReloader.reload(targets: targets) : []
        return ThemeApplyReport(writtenFiles: written, reloadAttempts: reloads)
    }

    private static func writer(for target: ThemeTarget) -> (TerminalPalettePair, URL) throws -> [URL] {
        switch target {
        case .kitty: writeKitty
        case .alacritty: writeAlacritty
        case .wezterm: writeWezTerm
        case .ghostty: writeGhostty
        case .iterm2: writeIterm2
        case .terminal: writeTerminalScript
        }
    }

    private static func writeKitty(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = home(".config/kitty/themes/mwall-dark.conf")
        let light = home(".config/kitty/themes/mwall-light.conf")
        let current = home(".config/kitty/themes/mwall.conf")
        try write(kittyConfig(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark"), to: dark)
        try write(kittyConfig(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light"), to: light)
        try write(kittyConfig(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current"), to: current)
        return [dark, light, current]
    }

    private static func kittyConfig(palette: TerminalPalette, wallpaperURL: URL, mode: String) -> String {
        let lines = header(wallpaperURL, mode: mode) + [
            "foreground \(palette.foreground.hex)",
            "background \(palette.background.hex)",
            "cursor \(palette.cursor.hex)",
            "cursor_text_color \(palette.cursorText.hex)",
            "selection_foreground \(palette.selectionForeground.hex)",
            "selection_background \(palette.selectionBackground.hex)"
        ] + ansiLines(prefix: "color", palette: palette)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeAlacritty(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = home(".config/alacritty/themes/mwall-dark.toml")
        let light = home(".config/alacritty/themes/mwall-light.toml")
        let current = home(".config/alacritty/themes/mwall.toml")
        try write(alacrittyConfig(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark"), to: dark)
        try write(alacrittyConfig(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light"), to: light)
        try write(alacrittyConfig(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current"), to: current)
        return [dark, light, current]
    }

    private static func alacrittyConfig(palette: TerminalPalette, wallpaperURL: URL, mode: String) -> String {
        var lines = header(wallpaperURL, mode: mode)
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
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeWezTerm(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = home(".config/wezterm/colors/mwall-dark.toml")
        let light = home(".config/wezterm/colors/mwall-light.toml")
        let current = home(".config/wezterm/colors/mwall.toml")
        try write(wezTermConfig(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark"), to: dark)
        try write(wezTermConfig(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light"), to: light)
        try write(wezTermConfig(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current"), to: current)
        return [dark, light, current]
    }

    private static func wezTermConfig(palette: TerminalPalette, wallpaperURL: URL, mode: String) -> String {
        let lines = header(wallpaperURL, mode: mode) + [
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
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeGhostty(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = home(".config/ghostty/themes/mwall-dark")
        let light = home(".config/ghostty/themes/mwall-light")
        let current = home(".config/ghostty/themes/mwall")
        try write(ghosttyConfig(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark"), to: dark)
        try write(ghosttyConfig(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light"), to: light)
        try write(ghosttyConfig(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current"), to: current)
        return [dark, light, current]
    }

    private static func ghosttyConfig(palette: TerminalPalette, wallpaperURL: URL, mode: String) -> String {
        var lines = header(wallpaperURL, mode: mode)
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
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeIterm2(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = StorePaths.appSupport.appendingPathComponent("MWall Dark.itermcolors")
        let light = StorePaths.appSupport.appendingPathComponent("MWall Light.itermcolors")
        let current = StorePaths.appSupport.appendingPathComponent("MWall.itermcolors")
        try write(itermColors(palette: palettes.dark), to: dark)
        try write(itermColors(palette: palettes.light), to: light)
        try write(itermColors(palette: palettes.current), to: current)
        return [dark, light, current]
    }

    private static func itermColors(palette: TerminalPalette) -> String {
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
        return plist
    }

    private static func writeTerminalScript(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = StorePaths.appSupport.appendingPathComponent("Apply-MWall-Terminal-Dark.applescript")
        let light = StorePaths.appSupport.appendingPathComponent("Apply-MWall-Terminal-Light.applescript")
        let current = StorePaths.appSupport.appendingPathComponent("Apply-MWall-Terminal.applescript")
        try write(terminalScript(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark"), to: dark)
        try write(terminalScript(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light"), to: light)
        try write(terminalScript(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current"), to: current)
        return [dark, light, current]
    }

    private static func terminalScript(palette: TerminalPalette, wallpaperURL: URL, mode: String) -> String {
        """
        -- Generated by MWall from \(wallpaperURL.path)
        -- Mode: \(mode)
        -- Run this script manually if you want to update the front Terminal.app tab.
        tell application "Terminal"
            if not (exists window 1) then reopen
            set background color of selected tab of front window to {\(appleRGB(palette.background))}
            set normal text color of selected tab of front window to {\(appleRGB(palette.foreground))}
            set cursor color of selected tab of front window to {\(appleRGB(palette.cursor))}
        end tell
        """
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func home(_ relativePath: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativePath)
    }

    private static func header(_ wallpaperURL: URL, mode: String) -> [String] {
        [
            "# Generated by MWall",
            "# Wallpaper: \(wallpaperURL.path)",
            "# Mode: \(mode)",
            "# Include/import this file from your terminal config if it is not loaded automatically.",
            ""
        ]
    }

    private static func ansiLines(prefix: String, palette: TerminalPalette) -> [String] {
        (palette.normal + palette.bright).enumerated().map { "\(prefix)\($0.offset) \(paletteHex($0.element))" }
    }

    private static func namedAnsi(_ colors: [RGBColor]) -> [(key: String, value: RGBColor)] {
        zip(["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"], colors).map { ($0, $1) }
    }

    private static func tomlArray(_ colors: [RGBColor]) -> String {
        "[" + colors.map { "'\($0.hex)'" }.joined(separator: ", ") + "]"
    }

    private static func paletteHex(_ color: RGBColor) -> String {
        color.hex
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
