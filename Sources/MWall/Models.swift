import Foundation

enum WallpaperKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case builtIn
    case local
    case unsplash
    case wallhaven
    case favorite
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "内置"
        case .local: "本地"
        case .unsplash: "Unsplash"
        case .wallhaven: "Wallhaven"
        case .favorite: "收藏"
        case .history: "历史"
        }
    }
}

struct WallpaperItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var url: URL
    var title: String
    var kind: WallpaperKind
    var source: String?
    var fullResolutionURL: URL?
    var downloadLocation: URL?
    var fullLocalURL: URL?

    // Favorites and history change the display kind, not the original provider.
    var onlineSource: WallpaperKind? {
        if id.hasPrefix("wallhaven:") { return .wallhaven }
        if id.hasPrefix("unsplash:") { return .unsplash }
        return nil
    }

    init(
        id: String? = nil,
        url: URL,
        title: String? = nil,
        kind: WallpaperKind,
        source: String? = nil,
        fullResolutionURL: URL? = nil,
        downloadLocation: URL? = nil,
        fullLocalURL: URL? = nil
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.kind = kind
        self.source = source
        self.fullResolutionURL = fullResolutionURL
        self.downloadLocation = downloadLocation
        self.fullLocalURL = fullLocalURL
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var item: WallpaperItem
    var appliedAt: Date = Date()
}

struct AppSettings: Codable, Equatable {
    var paletteStyle: PaletteStyle = .faithful
    var applyToAllScreens = true
    var applyThemeAfterWallpaperChange = true
    var reloadTerminalsAfterThemeChange = true
    var launchAtLogin = false
    var enabledThemeTargets: Set<ThemeTarget> = Set(ThemeTarget.defaultEnabled)
    var currentSource: WallpaperKind = .builtIn
    var unsplashAccessKey = ""
    var unsplashCacheLimitMB = 600
    var wallhavenSearch = WallhavenSearch()
    var wallhavenCacheLimitMB = 600

    init() {}

    private enum CodingKeys: String, CodingKey {
        case paletteStyle, applyToAllScreens, applyThemeAfterWallpaperChange
        case reloadTerminalsAfterThemeChange, launchAtLogin, enabledThemeTargets
        case currentSource, unsplashAccessKey, unsplashCacheLimitMB
        case wallhavenSearch, wallhavenCacheLimitMB
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paletteStyle =
            (try c.decodeIfPresent(String.self, forKey: .paletteStyle))
            .flatMap(PaletteStyle.init(rawValue:)) ?? .faithful
        applyToAllScreens = try c.decodeIfPresent(Bool.self, forKey: .applyToAllScreens) ?? true
        applyThemeAfterWallpaperChange =
            try c.decodeIfPresent(Bool.self, forKey: .applyThemeAfterWallpaperChange) ?? true
        reloadTerminalsAfterThemeChange =
            try c.decodeIfPresent(Bool.self, forKey: .reloadTerminalsAfterThemeChange) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        enabledThemeTargets =
            try c.decodeIfPresent(Set<ThemeTarget>.self, forKey: .enabledThemeTargets)
            ?? Set(ThemeTarget.defaultEnabled)
        currentSource =
            try c.decodeIfPresent(WallpaperKind.self, forKey: .currentSource) ?? .builtIn
        unsplashAccessKey = try c.decodeIfPresent(String.self, forKey: .unsplashAccessKey) ?? ""
        unsplashCacheLimitMB = try c.decodeIfPresent(Int.self, forKey: .unsplashCacheLimitMB) ?? 600
        wallhavenSearch =
            try c.decodeIfPresent(WallhavenSearch.self, forKey: .wallhavenSearch)
            ?? WallhavenSearch()
        wallhavenCacheLimitMB =
            try c.decodeIfPresent(Int.self, forKey: .wallhavenCacheLimitMB) ?? 600
    }
}

struct LocalFolderBookmark: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var url: URL
    var bookmarkData: Data?
    var isStale: Bool

    init(id: UUID = UUID(), url: URL, bookmarkData: Data? = nil, isStale: Bool = false) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData
        self.isStale = isStale
    }
}

enum ThemeTarget: String, Codable, CaseIterable, Identifiable {
    case kitty
    case alacritty
    case wezterm
    case ghostty
    case neovim
    case starship
    case pi
    case codexCLI = "codex-cli"
    case codexApp = "codex-app"
    case iterm2
    case terminal

    var id: String { rawValue }

    static let allCases: [ThemeTarget] = [
        .kitty, .ghostty, .neovim, .starship, .pi, .codexCLI, .codexApp,
    ]

    var displayName: String {
        switch self {
        case .kitty: "Kitty"
        case .ghostty: "Ghostty"
        case .neovim: "Neovim"
        case .starship: "Starship"
        case .pi: "Pi"
        case .codexCLI: "Codex CLI"
        case .codexApp: "Codex App"
        case .alacritty: "Alacritty"
        case .wezterm: "WezTerm"
        case .iterm2: "iTerm2"
        case .terminal: "Terminal.app"
        }
    }

    static let supported: Set<ThemeTarget> = Set(allCases)
    static let defaultEnabled: [ThemeTarget] = [
        .kitty, .ghostty, .neovim, .starship, .pi, .codexCLI,
    ]
}

enum StorePaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("MWall", isDirectory: true)
    }

    static var cache: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MWall", isDirectory: true)
    }

    static var builtIns: URL {
        appSupport.appendingPathComponent("BuiltIns", isDirectory: true)
    }

    /// Durable copies of applied wallpapers (unique `current-<uuid>.<ext>` per apply).
    /// Keeps System Settings previews and desktop references out of Caches, and forces a
    /// path change so macOS refreshes the desktop image.
    static var applied: URL {
        appSupport.appendingPathComponent("Applied", isDirectory: true)
    }

    static var unsplash: URL {
        cache.appendingPathComponent("Unsplash", isDirectory: true)
    }

    static var unsplashPreviews: URL {
        unsplash.appendingPathComponent("Previews", isDirectory: true)
    }

    static var unsplashFull: URL {
        unsplash.appendingPathComponent("Full", isDirectory: true)
    }

    static var unsplashMetadata: URL {
        unsplash.appendingPathComponent("metadata.json")
    }

    static var wallhaven: URL {
        cache.appendingPathComponent("Wallhaven", isDirectory: true)
    }

    static var settings: URL {
        appSupport.appendingPathComponent("settings.json")
    }

    static var folders: URL {
        appSupport.appendingPathComponent("folders.json")
    }

    static var folderBookmarks: URL {
        appSupport.appendingPathComponent("folder-bookmarks.json")
    }

    static var favorites: URL {
        appSupport.appendingPathComponent("favorites.json")
    }

    static var history: URL {
        appSupport.appendingPathComponent("history.json")
    }
}
