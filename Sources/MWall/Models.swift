import Foundation

enum WallpaperKind: String, Codable, CaseIterable, Identifiable {
    case builtIn
    case local
    case unsplash
    case favorite
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "内置"
        case .local: "本地"
        case .unsplash: "Unsplash"
        case .favorite: "收藏"
        case .history: "历史"
        }
    }
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    var id: String
    var url: URL
    var title: String
    var kind: WallpaperKind
    var source: String?

    init(url: URL, title: String? = nil, kind: WallpaperKind, source: String? = nil) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.kind = kind
        self.source = source
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var item: WallpaperItem
    var appliedAt: Date = Date()
}

struct AppSettings: Codable, Equatable {
    var applyToAllScreens = true
    var applyThemeAfterWallpaperChange = true
    var reloadTerminalsAfterThemeChange = true
    var launchAtLogin = false
    var enabledThemeTargets: Set<ThemeTarget> = Set(ThemeTarget.defaultEnabled)
    var currentSource: WallpaperKind = .builtIn
    var unsplashAccessKey = ""
    var unsplashQuery = "nature landscape"
    var unsplashCacheLimitMB = 600
}

struct LocalFolderBookmark: Identifiable, Codable, Hashable {
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
    case iterm2
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kitty: "Kitty"
        case .alacritty: "Alacritty"
        case .wezterm: "WezTerm"
        case .ghostty: "Ghostty"
        case .iterm2: "iTerm2"
        case .terminal: "Terminal.app"
        }
    }

    static let defaultEnabled: [ThemeTarget] = [.kitty, .alacritty, .wezterm, .ghostty]
}

enum StorePaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MWall", isDirectory: true)
    }

    static var cache: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MWall", isDirectory: true)
    }

    static var builtIns: URL {
        appSupport.appendingPathComponent("BuiltIns", isDirectory: true)
    }

    static var unsplash: URL {
        cache.appendingPathComponent("Unsplash", isDirectory: true)
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
