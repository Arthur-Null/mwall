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
        for target in targets.intersection(ThemeTarget.supported).sorted(by: { $0.rawValue < $1.rawValue }) {
            let files = try writer(for: target)(palettes, wallpaperURL)
            written.append(contentsOf: files)
        }
        let reloads = reloadTerminals ? TerminalReloader.reload(targets: targets.intersection(ThemeTarget.supported)) : []
        return ThemeApplyReport(writtenFiles: written, reloadAttempts: reloads)
    }

    private static func writer(for target: ThemeTarget) -> (TerminalPalettePair, URL) throws -> [URL] {
        switch target {
        case .kitty: writeKitty
        case .ghostty: writeGhostty
        case .neovim: writeNeovim
        case .alacritty, .wezterm, .iterm2, .terminal:
            { _, _ in [] }
        }
    }

    static func codexImportString(palettes: TerminalPalettePair) throws -> String {
        let palette = palettes.current
        let payload = CodexThemeImport(
            codeThemeId: "everforest",
            theme: CodexTheme(
                accent: palette.cursor.hex.lowercased(),
                contrast: 45,
                fonts: CodexThemeFonts(
                    code: "\"Maple Mono NF CN\"",
                    ui: "\"Maple Mono NF CN\""
                ),
                ink: palette.foreground.hex.lowercased(),
                opaqueWindows: false,
                semanticColors: CodexSemanticColors(
                    diffAdded: palette.normal[safe: 2]?.hex.lowercased() ?? palette.cursor.hex.lowercased(),
                    diffRemoved: palette.normal[safe: 1]?.hex.lowercased() ?? palette.cursor.hex.lowercased(),
                    skill: palette.normal[safe: 5]?.hex.lowercased() ?? palette.cursor.hex.lowercased()
                ),
                surface: palette.background.hex.lowercased()
            ),
            variant: palette.background.luminance < 0.5 ? "dark" : "light"
        )
        let data = try JSONEncoder.codexTheme.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MWall.CodexTheme", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法生成 Codex 主题字符串"])
        }
        return "codex-theme-v1:\(json)"
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

    private static func writeNeovim(_ palettes: TerminalPalettePair, _ wallpaperURL: URL) throws -> [URL] {
        let dark = home(".config/nvim/colors/mwall-dark.lua")
        let light = home(".config/nvim/colors/mwall-light.lua")
        let current = home(".config/nvim/colors/mwall.lua")
        try write(neovimConfig(palette: palettes.dark, wallpaperURL: wallpaperURL, mode: "dark", schemeName: "mwall-dark"), to: dark)
        try write(neovimConfig(palette: palettes.light, wallpaperURL: wallpaperURL, mode: "light", schemeName: "mwall-light"), to: light)
        try write(neovimConfig(palette: palettes.current, wallpaperURL: wallpaperURL, mode: "current", schemeName: "mwall"), to: current)
        return [dark, light, current]
    }

    private static func neovimConfig(
        palette: TerminalPalette,
        wallpaperURL: URL,
        mode: String,
        schemeName: String
    ) -> String {
        let isDark = palette.background.luminance < 0.5
        let subtle = palette.foreground.blended(with: palette.background, amount: isDark ? 0.58 : 0.46)
        let surface = palette.background.blended(with: palette.foreground, amount: isDark ? 0.08 : 0.05)
        let panel = palette.background.blended(with: palette.foreground, amount: isDark ? 0.12 : 0.08)
        let active = palette.cursor.blended(with: palette.background, amount: isDark ? 0.78 : 0.84)
        let red = palette.normal[safe: 1] ?? palette.cursor
        let green = palette.normal[safe: 2] ?? palette.cursor
        let yellow = palette.normal[safe: 3] ?? palette.cursor
        let blue = palette.normal[safe: 4] ?? palette.cursor
        let magenta = palette.normal[safe: 5] ?? palette.cursor
        let cyan = palette.normal[safe: 6] ?? palette.cursor
        let white = palette.normal[safe: 7] ?? palette.foreground
        let brightRed = palette.bright[safe: 1] ?? red
        let brightGreen = palette.bright[safe: 2] ?? green
        let brightYellow = palette.bright[safe: 3] ?? yellow
        let brightBlue = palette.bright[safe: 4] ?? blue
        let brightCyan = palette.bright[safe: 6] ?? cyan
        let diffAdd = green.blended(with: palette.background, amount: isDark ? 0.82 : 0.88)
        let diffDelete = red.blended(with: palette.background, amount: isDark ? 0.82 : 0.88)
        let diffChange = blue.blended(with: palette.background, amount: isDark ? 0.82 : 0.88)
        let diffText = yellow.blended(with: palette.background, amount: isDark ? 0.76 : 0.84)

        var lines = [
            "-- Generated by MWall",
            "-- Wallpaper: \(luaString(wallpaperURL.path))",
            "-- Mode: \(mode)",
            "vim.cmd(\"highlight clear\")",
            "if vim.fn.exists(\"syntax_on\") == 1 then",
            "  vim.cmd(\"syntax reset\")",
            "end",
            "vim.o.background = \"\(isDark ? "dark" : "light")\"",
            "vim.g.colors_name = \"\(schemeName)\"",
            "",
            "local set = vim.api.nvim_set_hl",
            ""
        ]

        let highlights: [(String, String)] = [
            ("Normal", nvimHighlight(fg: palette.foreground, bg: palette.background)),
            ("NormalNC", nvimHighlight(fg: palette.foreground, bg: palette.background)),
            ("NormalFloat", nvimHighlight(fg: palette.foreground, bg: panel)),
            ("FloatBorder", nvimHighlight(fg: subtle, bg: panel)),
            ("FloatTitle", nvimHighlight(fg: palette.cursor, bg: panel, bold: true)),
            ("SignColumn", nvimHighlight(fg: subtle, bg: palette.background)),
            ("LineNr", nvimHighlight(fg: subtle, bg: palette.background)),
            ("CursorLine", nvimHighlight(bg: surface)),
            ("CursorLineNr", nvimHighlight(fg: palette.cursor, bg: surface, bold: true)),
            ("ColorColumn", nvimHighlight(bg: surface)),
            ("WinSeparator", nvimHighlight(fg: surface)),
            ("StatusLine", nvimHighlight(fg: palette.foreground, bg: panel)),
            ("StatusLineNC", nvimHighlight(fg: subtle, bg: surface)),
            ("TabLine", nvimHighlight(fg: subtle, bg: surface)),
            ("TabLineSel", nvimHighlight(fg: palette.foreground, bg: panel, bold: true)),
            ("Pmenu", nvimHighlight(fg: palette.foreground, bg: panel)),
            ("PmenuSel", nvimHighlight(fg: palette.foreground, bg: active)),
            ("PmenuSbar", nvimHighlight(bg: panel)),
            ("PmenuThumb", nvimHighlight(bg: subtle)),
            ("Visual", nvimHighlight(bg: palette.selectionBackground)),
            ("Search", nvimHighlight(fg: palette.cursorText, bg: yellow)),
            ("IncSearch", nvimHighlight(fg: palette.cursorText, bg: palette.cursor)),
            ("CurSearch", nvimHighlight(fg: palette.cursorText, bg: palette.cursor)),
            ("MatchParen", nvimHighlight(fg: palette.cursor, bg: active, bold: true)),
            ("Directory", nvimHighlight(fg: blue, bold: true)),
            ("Title", nvimHighlight(fg: palette.cursor, bold: true)),
            ("Question", nvimHighlight(fg: green)),
            ("MoreMsg", nvimHighlight(fg: green)),
            ("ModeMsg", nvimHighlight(fg: palette.foreground)),
            ("NonText", nvimHighlight(fg: subtle)),
            ("Whitespace", nvimHighlight(fg: subtle)),
            ("SpecialKey", nvimHighlight(fg: subtle)),
            ("Comment", nvimHighlight(fg: subtle, italic: true)),
            ("Constant", nvimHighlight(fg: cyan)),
            ("String", nvimHighlight(fg: green)),
            ("Character", nvimHighlight(fg: green)),
            ("Number", nvimHighlight(fg: magenta)),
            ("Boolean", nvimHighlight(fg: magenta)),
            ("Float", nvimHighlight(fg: magenta)),
            ("Identifier", nvimHighlight(fg: palette.foreground)),
            ("Function", nvimHighlight(fg: blue, bold: true)),
            ("Statement", nvimHighlight(fg: magenta)),
            ("Conditional", nvimHighlight(fg: magenta)),
            ("Repeat", nvimHighlight(fg: magenta)),
            ("Label", nvimHighlight(fg: magenta)),
            ("Operator", nvimHighlight(fg: cyan)),
            ("Keyword", nvimHighlight(fg: magenta, bold: true)),
            ("Exception", nvimHighlight(fg: red)),
            ("PreProc", nvimHighlight(fg: yellow)),
            ("Include", nvimHighlight(fg: blue)),
            ("Define", nvimHighlight(fg: magenta)),
            ("Macro", nvimHighlight(fg: yellow)),
            ("PreCondit", nvimHighlight(fg: yellow)),
            ("Type", nvimHighlight(fg: yellow)),
            ("StorageClass", nvimHighlight(fg: yellow)),
            ("Structure", nvimHighlight(fg: yellow)),
            ("Typedef", nvimHighlight(fg: yellow)),
            ("Special", nvimHighlight(fg: cyan)),
            ("SpecialChar", nvimHighlight(fg: brightCyan)),
            ("Tag", nvimHighlight(fg: blue)),
            ("Delimiter", nvimHighlight(fg: subtle)),
            ("Debug", nvimHighlight(fg: red)),
            ("Underlined", nvimHighlight(fg: blue, underline: true)),
            ("Bold", nvimHighlight(bold: true)),
            ("Italic", nvimHighlight(italic: true)),
            ("Error", nvimHighlight(fg: brightRed, bold: true)),
            ("Todo", nvimHighlight(fg: brightYellow, bg: active, bold: true)),
            ("DiagnosticError", nvimHighlight(fg: brightRed)),
            ("DiagnosticWarn", nvimHighlight(fg: brightYellow)),
            ("DiagnosticInfo", nvimHighlight(fg: brightBlue)),
            ("DiagnosticHint", nvimHighlight(fg: brightCyan)),
            ("DiagnosticOk", nvimHighlight(fg: brightGreen)),
            ("DiagnosticUnderlineError", nvimHighlight(sp: brightRed, undercurl: true)),
            ("DiagnosticUnderlineWarn", nvimHighlight(sp: brightYellow, undercurl: true)),
            ("DiagnosticUnderlineInfo", nvimHighlight(sp: brightBlue, undercurl: true)),
            ("DiagnosticUnderlineHint", nvimHighlight(sp: brightCyan, undercurl: true)),
            ("DiffAdd", nvimHighlight(fg: green, bg: diffAdd)),
            ("DiffDelete", nvimHighlight(fg: red, bg: diffDelete)),
            ("DiffChange", nvimHighlight(fg: blue, bg: diffChange)),
            ("DiffText", nvimHighlight(fg: yellow, bg: diffText, bold: true)),
            ("GitSignsAdd", nvimHighlight(fg: green)),
            ("GitSignsChange", nvimHighlight(fg: blue)),
            ("GitSignsDelete", nvimHighlight(fg: red)),
            ("TelescopeNormal", nvimHighlight(fg: palette.foreground, bg: panel)),
            ("TelescopeBorder", nvimHighlight(fg: subtle, bg: panel)),
            ("TelescopeSelection", nvimHighlight(fg: palette.foreground, bg: active)),
            ("TelescopeMatching", nvimHighlight(fg: palette.cursor, bold: true)),
            ("NeoTreeNormal", nvimHighlight(fg: palette.foreground, bg: palette.background)),
            ("NeoTreeDirectoryName", nvimHighlight(fg: blue)),
            ("NeoTreeFileName", nvimHighlight(fg: palette.foreground)),
            ("NeoTreeGitAdded", nvimHighlight(fg: green)),
            ("NeoTreeGitModified", nvimHighlight(fg: yellow)),
            ("NeoTreeGitDeleted", nvimHighlight(fg: red)),
            ("CmpItemAbbrMatch", nvimHighlight(fg: palette.cursor, bold: true)),
            ("CmpItemKind", nvimHighlight(fg: magenta)),
            ("@comment", nvimHighlight(fg: subtle, italic: true)),
            ("@constant", nvimHighlight(fg: cyan)),
            ("@string", nvimHighlight(fg: green)),
            ("@number", nvimHighlight(fg: magenta)),
            ("@boolean", nvimHighlight(fg: magenta)),
            ("@function", nvimHighlight(fg: blue, bold: true)),
            ("@function.method", nvimHighlight(fg: blue)),
            ("@constructor", nvimHighlight(fg: yellow)),
            ("@keyword", nvimHighlight(fg: magenta, bold: true)),
            ("@operator", nvimHighlight(fg: cyan)),
            ("@variable", nvimHighlight(fg: palette.foreground)),
            ("@variable.builtin", nvimHighlight(fg: red)),
            ("@property", nvimHighlight(fg: cyan)),
            ("@type", nvimHighlight(fg: yellow)),
            ("@tag", nvimHighlight(fg: blue)),
            ("@punctuation", nvimHighlight(fg: white))
        ]

        lines += highlights.map { "set(0, \"\($0.0)\", \($0.1))" }
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

    private static func nvimHighlight(
        fg: RGBColor? = nil,
        bg: RGBColor? = nil,
        sp: RGBColor? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        undercurl: Bool = false
    ) -> String {
        var fields: [String] = []
        if let fg {
            fields.append("fg = \"\(fg.hex)\"")
        }
        if let bg {
            fields.append("bg = \"\(bg.hex)\"")
        }
        if let sp {
            fields.append("sp = \"\(sp.hex)\"")
        }
        if bold {
            fields.append("bold = true")
        }
        if italic {
            fields.append("italic = true")
        }
        if underline {
            fields.append("underline = true")
        }
        if undercurl {
            fields.append("undercurl = true")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    private static func luaString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

private struct CodexThemeImport: Encodable {
    var codeThemeId: String
    var theme: CodexTheme
    var variant: String
}

private struct CodexTheme: Encodable {
    var accent: String
    var contrast: Int
    var fonts: CodexThemeFonts
    var ink: String
    var opaqueWindows: Bool
    var semanticColors: CodexSemanticColors
    var surface: String
}

private struct CodexThemeFonts: Encodable {
    var code: String
    var ui: String
}

private struct CodexSemanticColors: Encodable {
    var diffAdded: String
    var diffRemoved: String
    var skill: String
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension JSONEncoder {
    static var codexTheme: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
