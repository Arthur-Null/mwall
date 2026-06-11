import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var builtInWallpapers: [WallpaperItem] = []
    @Published private(set) var localWallpapers: [WallpaperItem] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var favorites: [WallpaperItem] = []
    @Published var settings = AppSettings() {
        didSet { Persistence.save(settings, to: StorePaths.settings) }
    }
    @Published var localFolders: [LocalFolderBookmark] = [] {
        didSet { Persistence.save(localFolders, to: StorePaths.folderBookmarks) }
    }
    @Published var lastMessage = ""
    @Published var selectedWallpaperID: String?
    @Published var isWorking = false

    private let maxHistoryCount = 80

    func bootstrap() {
        Persistence.prepareDirectories()
        WallpaperService.ensureBuiltInWallpapers()

        settings = Persistence.load(AppSettings.self, from: StorePaths.settings, fallback: AppSettings())
        localFolders = loadLocalFolders()
        favorites = Persistence.load([WallpaperItem].self, from: StorePaths.favorites, fallback: [])
        history = Persistence.load([HistoryEntry].self, from: StorePaths.history, fallback: [])
        settings.launchAtLogin = LoginItemService.isEnabled
        refreshLibrary()
    }

    var visibleWallpapers: [WallpaperItem] {
        switch settings.currentSource {
        case .builtIn:
            builtInWallpapers
        case .local:
            localWallpapers
        case .unsplash:
            WallpaperService.imageFiles(in: StorePaths.unsplash).map {
                WallpaperItem(url: $0, kind: .unsplash, source: "Unsplash")
            }
        case .favorite:
            favorites
        case .history:
            history.map { var item = $0.item; item.kind = .history; return item }
        }
    }

    func refreshLibrary() {
        builtInWallpapers = WallpaperService.imageFiles(in: StorePaths.builtIns).map {
            WallpaperItem(url: $0, kind: .builtIn, source: "MWall")
        }
        localWallpapers = localFolders.flatMap { folder in
            SecurityScopedBookmarks.withAccess(to: folder.url) {
                WallpaperService.imageFiles(in: folder.url).map {
                    WallpaperItem(url: $0, kind: .local, source: folder.url.lastPathComponent)
                }
            }
        }
        lastMessage = "已扫描 \(builtInWallpapers.count + localWallpapers.count) 张壁纸"
    }

    func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择壁纸文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else {
            return
        }
        var known = Set(localFolders.map { $0.url.standardizedFileURL.path })
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if known.insert(path).inserted {
                localFolders.append(LocalFolderBookmark(url: url, bookmarkData: SecurityScopedBookmarks.makeBookmark(for: url)))
            }
        }
        settings.currentSource = .local
        refreshLibrary()
    }

    func removeLocalFolder(_ folder: URL) {
        localFolders.removeAll { $0.url.standardizedFileURL == folder.standardizedFileURL }
        refreshLibrary()
    }

    func setSource(_ source: WallpaperKind) {
        settings.currentSource = source
    }

    func toggleFavorite(_ item: WallpaperItem) {
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            var favorite = item
            favorite.kind = .favorite
            favorites.insert(favorite, at: 0)
        }
        Persistence.save(favorites, to: StorePaths.favorites)
    }

    func isFavorite(_ item: WallpaperItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func applyRandomWallpaper() {
        guard let item = visibleWallpapers.randomElement() ?? builtInWallpapers.randomElement() else {
            lastMessage = "没有可用壁纸"
            return
        }
        applyWallpaper(item)
    }

    func applyWallpaper(_ item: WallpaperItem) {
        do {
            try SecurityScopedBookmarks.withAccess(for: item.url, folders: localFolders) {
                try WallpaperService.setDesktopImage(item.url, allScreens: settings.applyToAllScreens)
                selectedWallpaperID = item.id
                addHistory(item)
                lastMessage = "已应用：\(item.title)"

                guard settings.applyThemeAfterWallpaperChange else {
                    return
                }
                let palette = try PaletteGenerator.generate(from: item.url)
                let report = try ThemeManager.apply(
                    palette: palette,
                    wallpaperURL: item.url,
                    targets: settings.enabledThemeTargets,
                    reloadTerminals: settings.reloadTerminalsAfterThemeChange
                )
                lastMessage = "已应用壁纸，并写入 \(report.writtenFiles.count) 个主题文件"
            }
        } catch {
            lastMessage = "失败：\(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func toggleThemeTarget(_ target: ThemeTarget) {
        if settings.enabledThemeTargets.contains(target) {
            settings.enabledThemeTargets.remove(target)
        } else {
            settings.enabledThemeTargets.insert(target)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            settings.launchAtLogin = enabled
            lastMessage = enabled ? "已设置开机启动" : "已关闭开机启动"
        } catch {
            settings.launchAtLogin = LoginItemService.isEnabled
            lastMessage = error.localizedDescription
            NSAlert(error: error).runModal()
        }
    }

    func applyThemeForSelectedOrLatest() {
        guard let item = currentWallpaperCandidate() else {
            lastMessage = "没有可用于生成主题的壁纸"
            return
        }
        do {
            try SecurityScopedBookmarks.withAccess(for: item.url, folders: localFolders) {
                let palette = try PaletteGenerator.generate(from: item.url)
                let report = try ThemeManager.apply(
                    palette: palette,
                    wallpaperURL: item.url,
                    targets: settings.enabledThemeTargets,
                    reloadTerminals: settings.reloadTerminalsAfterThemeChange
                )
                lastMessage = "已写入 \(report.writtenFiles.count) 个主题文件"
            }
        } catch {
            lastMessage = "主题生成失败：\(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func cleanupCache() {
        do {
            let removed = try CacheManager.cleanupUnsplashCache(limitMB: settings.unsplashCacheLimitMB)
            lastMessage = removed == 0 ? "缓存无需清理" : "已清理 \(removed) 个缓存文件"
            refreshLibrary()
        } catch {
            lastMessage = "缓存清理失败：\(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func fetchUnsplashWallpaper() {
        isWorking = true
        lastMessage = "正在从 Unsplash 获取壁纸..."
        Task {
            do {
                let result = try await UnsplashService.downloadRandom(
                    accessKey: settings.unsplashAccessKey,
                    query: settings.unsplashQuery
                )
                await MainActor.run {
                    isWorking = false
                    settings.currentSource = .unsplash
                    lastMessage = "已下载 Unsplash 壁纸：\(result.author)"
                    refreshLibrary()
                    applyWallpaper(result.item)
                    cleanupCache()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    lastMessage = "Unsplash 失败：\(error.localizedDescription)"
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    func pasteUnsplashAccessKey() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            lastMessage = "剪贴板里没有可用文本"
            return
        }
        settings.unsplashAccessKey = text
        lastMessage = "已从剪贴板填入 Unsplash Access Key"
    }

    private func currentWallpaperCandidate() -> WallpaperItem? {
        if let selectedWallpaperID,
           let selected = (builtInWallpapers + localWallpapers + favorites).first(where: { $0.id == selectedWallpaperID }) {
            return selected
        }
        return history.first?.item ?? visibleWallpapers.first ?? builtInWallpapers.first
    }

    private func addHistory(_ item: WallpaperItem) {
        history.removeAll { $0.item.id == item.id }
        history.insert(HistoryEntry(item: item), at: 0)
        if history.count > maxHistoryCount {
            history.removeLast(history.count - maxHistoryCount)
        }
        Persistence.save(history, to: StorePaths.history)
    }

    private func loadLocalFolders() -> [LocalFolderBookmark] {
        let loaded = Persistence.load([LocalFolderBookmark].self, from: StorePaths.folderBookmarks, fallback: [])
        if !loaded.isEmpty {
            return loaded.map(SecurityScopedBookmarks.resolve)
        }

        let legacyPaths = Persistence.load([String].self, from: StorePaths.folders, fallback: [])
        return legacyPaths.map { path in
            let url = URL(fileURLWithPath: path)
            return LocalFolderBookmark(url: url, bookmarkData: SecurityScopedBookmarks.makeBookmark(for: url))
        }
    }
}
