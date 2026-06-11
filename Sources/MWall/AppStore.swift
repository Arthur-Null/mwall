import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var builtInWallpapers: [WallpaperItem] = []
    @Published private(set) var localWallpapers: [WallpaperItem] = []
    @Published private(set) var unsplashWallpapers: [WallpaperItem] = []
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
        pruneUnsupportedThemeTargets()
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
            unsplashWallpapers
        case .favorite:
            favorites
        case .history:
            history.map { var item = $0.item; item.kind = .history; return item }
        }
    }

    func refreshLibrary(updateMessage: Bool = true) {
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
        unsplashWallpapers = UnsplashService.localItems()
        if updateMessage {
            lastMessage = "已扫描 \(builtInWallpapers.count + localWallpapers.count) 张壁纸"
        }
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
        if source == .unsplash {
            ensureUnsplashPool()
        }
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
        if item.fullResolutionURL != nil {
            applyUnsplashWallpaper(item)
            return
        }
        applyResolvedWallpaper(item, wallpaperURL: item.url)
    }

    private func applyResolvedWallpaper(_ item: WallpaperItem, wallpaperURL: URL) {
        do {
            try SecurityScopedBookmarks.withAccess(for: wallpaperURL, folders: localFolders) {
                try WallpaperService.setDesktopImage(wallpaperURL, allScreens: settings.applyToAllScreens)
                selectedWallpaperID = item.id
                addHistory(item)
                lastMessage = "已应用：\(item.title)"

                guard settings.applyThemeAfterWallpaperChange else {
                    return
                }
                let palettes = try PaletteGenerator.generate(from: wallpaperURL)
                let report = try ThemeManager.apply(
                    palettes: palettes,
                    wallpaperURL: wallpaperURL,
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

    private func applyUnsplashWallpaper(_ item: WallpaperItem) {
        isWorking = true
        lastMessage = "正在准备 Unsplash 原图..."
        Task {
            do {
                let (fullURL, updatedItem) = try await UnsplashService.fullWallpaperURL(
                    for: item,
                    accessKey: settings.unsplashAccessKey
                )
                await MainActor.run {
                    isWorking = false
                    upsertUnsplashWallpaper(updatedItem)
                    applyResolvedWallpaper(updatedItem, wallpaperURL: fullURL)
                    cleanupCacheSilently()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    lastMessage = "Unsplash 原图失败：\(error.localizedDescription)"
                    NSAlert(error: error).runModal()
                }
            }
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
            let wallpaperURL = item.fullLocalURL ?? item.url
            try SecurityScopedBookmarks.withAccess(for: wallpaperURL, folders: localFolders) {
                let palettes = try PaletteGenerator.generate(from: wallpaperURL)
                let report = try ThemeManager.apply(
                    palettes: palettes,
                    wallpaperURL: wallpaperURL,
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

    func copyCodexThemeForSelectedOrLatest() {
        guard let item = currentWallpaperCandidate() else {
            lastMessage = "没有可用于生成 Codex 主题的壁纸"
            return
        }
        do {
            let wallpaperURL = item.fullLocalURL ?? item.url
            try SecurityScopedBookmarks.withAccess(for: wallpaperURL, folders: localFolders) {
                let palettes = try PaletteGenerator.generate(from: wallpaperURL)
                let importString = try ThemeManager.codexImportString(palettes: palettes)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(importString, forType: .string)
                lastMessage = "已复制 Codex 主题导入字符串"
            }
        } catch {
            lastMessage = "Codex 主题复制失败：\(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func cleanupCache() {
        do {
            let removed = try CacheManager.cleanupUnsplashCache(limitMB: settings.unsplashCacheLimitMB)
            lastMessage = removed == 0 ? "缓存无需清理" : "已清理 \(removed) 个缓存文件"
            refreshLibrary(updateMessage: false)
        } catch {
            lastMessage = "缓存清理失败：\(error.localizedDescription)"
            NSAlert(error: error).runModal()
        }
    }

    func ensureUnsplashPool() {
        unsplashWallpapers = UnsplashService.localItems()
        guard unsplashWallpapers.count < UnsplashService.preferredPoolSize else {
            lastMessage = "已加载 \(unsplashWallpapers.count) 张 Unsplash 精选"
            return
        }
        refreshUnsplashBatch()
    }

    func refreshUnsplashBatch() {
        isWorking = true
        lastMessage = "正在从 Unsplash 换一批精选..."
        Task {
            do {
                let newItems = try await UnsplashService.fetchWallpaperBatch(accessKey: settings.unsplashAccessKey)
                await MainActor.run {
                    isWorking = false
                    settings.currentSource = .unsplash
                    mergeUnsplashWallpapers(newItems)
                    lastMessage = "已加入 \(newItems.count) 张 Unsplash 精选"
                    cleanupCacheSilently()
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

    private func pruneUnsupportedThemeTargets() {
        settings.enabledThemeTargets.formIntersection(ThemeTarget.supported)
        if settings.enabledThemeTargets.isEmpty {
            settings.enabledThemeTargets = Set(ThemeTarget.defaultEnabled)
        }
    }

    private func currentWallpaperCandidate() -> WallpaperItem? {
        if let selectedWallpaperID,
           let selected = (builtInWallpapers + localWallpapers + unsplashWallpapers + favorites).first(where: { $0.id == selectedWallpaperID }) {
            return selected
        }
        return history.first?.item ?? visibleWallpapers.first ?? builtInWallpapers.first
    }

    private func mergeUnsplashWallpapers(_ newItems: [WallpaperItem]) {
        var merged = newItems + unsplashWallpapers
        var seen = Set<String>()
        merged.removeAll { item in
            !seen.insert(item.id).inserted
        }
        unsplashWallpapers = merged.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        UnsplashService.saveCachedItems(unsplashWallpapers)
    }

    private func upsertUnsplashWallpaper(_ item: WallpaperItem) {
        if let index = unsplashWallpapers.firstIndex(where: { $0.id == item.id }) {
            unsplashWallpapers[index] = item
        } else {
            unsplashWallpapers.insert(item, at: 0)
        }
        UnsplashService.saveCachedItems(unsplashWallpapers)
    }

    private func cleanupCacheSilently() {
        _ = try? CacheManager.cleanupUnsplashCache(limitMB: settings.unsplashCacheLimitMB)
        unsplashWallpapers = UnsplashService.localItems()
        UnsplashService.saveCachedItems(unsplashWallpapers)
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
