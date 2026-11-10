import Foundation
import ImageIO

enum WallhavenCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, anime, people
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "综合"
        case .anime: "二次元"
        case .people: "人物"
        }
    }
}

enum WallhavenPurity: String, Codable, CaseIterable, Identifiable, Sendable {
    case sfw, sketchy, nsfw
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sfw: "SFW"
        case .sketchy: "Sketchy"
        case .nsfw: "NSFW"
        }
    }
}

enum WallhavenSorting: String, Codable, CaseIterable, Identifiable, Sendable {
    case latest = "date_added"
    case relevance
    case random
    case views
    case favorites
    case toplist
    case hot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .latest: "最新"
        case .relevance: "相关度"
        case .random: "随机"
        case .views: "浏览最多"
        case .favorites: "收藏最多"
        case .toplist: "排行榜"
        case .hot: "最热"
        }
    }
}

enum WallhavenOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case desc, asc
    var id: String { rawValue }
    var title: String { self == .desc ? "降序" : "升序" }
}

enum WallhavenTopRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case day = "1d", threeDays = "3d", week = "1w", month = "1M"
    case threeMonths = "3M", sixMonths = "6M", year = "1y"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "1 天"
        case .threeDays: "3 天"
        case .week: "1 周"
        case .month: "1 个月"
        case .threeMonths: "3 个月"
        case .sixMonths: "6 个月"
        case .year: "1 年"
        }
    }
}

enum WallhavenResolutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case atLeast, exact
    var id: String { rawValue }
    var title: String { self == .atLeast ? "最低" : "精确" }
}

/// Option values mirror the wallhaven.cc search toolbar.
enum WallhavenOptions {
    static let resolutionGroups: [(title: String, values: [String])] = [
        ("超宽", ["2560x1080", "3440x1440", "3840x1600"]),
        ("16:9", ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]),
        ("16:10", ["1280x800", "1600x1000", "1920x1200", "2560x1600", "3840x2400"]),
        ("4:3", ["1280x960", "1600x1200", "1920x1440", "2560x1920", "3840x2880"]),
        ("5:4", ["1280x1024", "1600x1280", "1920x1536", "2560x2048", "3840x3072"]),
    ]
    static let ratioGroups: [(title: String, values: [String])] = [
        ("方向", ["landscape", "portrait"]),
        ("宽屏", ["16x9", "16x10"]),
        ("超宽", ["21x9", "32x9", "48x9"]),
        ("竖屏", ["9x16", "10x16", "9x18"]),
        ("方形", ["1x1", "3x2", "4x3", "5x4"]),
    ]
    static let colors = [
        "660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399",
        "0066cc", "0099cc", "66cccc", "77cc33", "669900", "336600", "666600", "999900",
        "cccc33", "ffff00", "ffcc33", "ff9900", "ff6600", "cc6633", "996633", "663300",
        "000000", "999999", "cccccc", "ffffff", "424153",
    ]
    static var resolutions: [String] { resolutionGroups.flatMap(\.values) }
    static var ratios: [String] { ratioGroups.flatMap(\.values) }

    static func resolutionTitle(_ value: String) -> String {
        value.replacingOccurrences(of: "x", with: "×")
    }

    static func ratioTitle(_ value: String) -> String {
        switch value {
        case "landscape": "横屏"
        case "portrait": "竖屏"
        default: value.replacingOccurrences(of: "x", with: ":")
        }
    }
}

struct WallhavenSearch: Codable, Equatable, Sendable {
    var query = ""
    var categories: Set<WallhavenCategory> = [.anime]
    var purity: Set<WallhavenPurity> = [.sfw]
    var sorting: WallhavenSorting = .random
    var order: WallhavenOrder = .desc
    var topRange: WallhavenTopRange = .month
    var resolutionMode: WallhavenResolutionMode = .atLeast
    /// Empty means no minimum.
    var atLeast = "1920x1080"
    var resolutions: Set<String> = []
    /// Empty means every aspect ratio.
    var ratios: Set<String> = ["landscape"]
    var color: String?

    init(
        query: String = "", categories: Set<WallhavenCategory> = [.anime],
        sorting: WallhavenSorting = .random
    ) {
        self.query = query
        self.categories = categories
        self.sorting = sorting
    }

    /// Keeps the query and resets every filter to its default.
    func resettingFilters() -> WallhavenSearch {
        WallhavenSearch(query: query)
    }

    private enum CodingKeys: String, CodingKey {
        case query, categories, purity, sorting, order, topRange
        case resolutionMode, atLeast, resolutions, ratios, color
    }

    private enum LegacyKeys: String, CodingKey { case category }

    // Every field is optional so older settings and cache metadata keep their query.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        if let categories = try? c.decodeIfPresent(Set<WallhavenCategory>.self, forKey: .categories),
            !categories.isEmpty
        {
            self.categories = categories
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            switch try? legacy.decodeIfPresent(String.self, forKey: .category) {
            case "all": categories = Set(WallhavenCategory.allCases)
            case let value?: categories = WallhavenCategory(rawValue: value).map { [$0] } ?? [.anime]
            case nil: categories = [.anime]
            }
        }
        purity = (try? c.decodeIfPresent(Set<WallhavenPurity>.self, forKey: .purity))
            .flatMap { $0?.isEmpty == false ? $0 : nil } ?? [.sfw]
        sorting = (try? c.decodeIfPresent(WallhavenSorting.self, forKey: .sorting)) ?? .random
        order = (try? c.decodeIfPresent(WallhavenOrder.self, forKey: .order)) ?? .desc
        topRange = (try? c.decodeIfPresent(WallhavenTopRange.self, forKey: .topRange)) ?? .month
        resolutionMode =
            (try? c.decodeIfPresent(WallhavenResolutionMode.self, forKey: .resolutionMode))
            ?? .atLeast
        atLeast = (try? c.decodeIfPresent(String.self, forKey: .atLeast)) ?? "1920x1080"
        resolutions = (try? c.decodeIfPresent(Set<String>.self, forKey: .resolutions)) ?? []
        ratios = (try? c.decodeIfPresent(Set<String>.self, forKey: .ratios)) ?? ["landscape"]
        color = try? c.decodeIfPresent(String.self, forKey: .color)
    }

    /// Parses a wallhaven.cc search or API URL into a search. Returns nil for other URLs.
    init?(webURL text: String) {
        guard let components = URLComponents(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme == "https" || components.scheme == "http",
            components.host == "wallhaven.cc" || components.host == "www.wallhaven.cc",
            components.path == "/search" || components.path == "/api/v1/search"
        else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
        self.init(query: values["q"] ?? "")
        // The website omits parameters that match the account defaults, which are all-on.
        categories = Self.bits(values["categories"], WallhavenCategory.allCases)
            ?? Set(WallhavenCategory.allCases)
        purity = Self.bits(values["purity"], WallhavenPurity.allCases) ?? [.sfw]
        sorting = values["sorting"].flatMap(WallhavenSorting.init(rawValue:)) ?? .latest
        order = values["order"].flatMap(WallhavenOrder.init(rawValue:)) ?? .desc
        topRange = values["topRange"].flatMap(WallhavenTopRange.init(rawValue:)) ?? .month
        let exact = Self.list(values["resolutions"]).filter(Self.isResolution)
        if !exact.isEmpty {
            resolutionMode = .exact
            resolutions = exact
        }
        atLeast = values["atleast"].flatMap { Self.isResolution($0) ? $0 : nil } ?? ""
        ratios = Self.list(values["ratios"]).filter(Self.isRatio)
        color = values["colors"].map { $0.lowercased() }.flatMap { Self.isColor($0) ? $0 : nil }
    }

    static func isResolution(_ value: String) -> Bool {
        value.wholeMatch(of: /[1-9][0-9]{2,4}x[1-9][0-9]{2,4}/) != nil
    }

    static func isRatio(_ value: String) -> Bool {
        value == "landscape" || value == "portrait"
            || value.wholeMatch(of: /[1-9][0-9]?x[1-9][0-9]?/) != nil
    }

    static func isColor(_ value: String) -> Bool {
        value.wholeMatch(of: /[0-9a-f]{6}/) != nil
    }

    /// Short description of the active filters for the result footer.
    var summary: String {
        var parts = [WallhavenPurity.allCases.filter(purity.contains).map(\.title).joined(separator: "/")]
        if categories.count < WallhavenCategory.allCases.count {
            parts.append(WallhavenCategory.allCases.filter(categories.contains).map(\.title)
                .joined(separator: "/"))
        }
        if !ratios.isEmpty {
            parts.append(WallhavenOptions.ratios.filter(ratios.contains)
                .map(WallhavenOptions.ratioTitle).joined(separator: ", "))
        }
        switch resolutionMode {
        case .atLeast where !atLeast.isEmpty:
            parts.append("≥\(WallhavenOptions.resolutionTitle(atLeast))")
        case .exact where !resolutions.isEmpty:
            parts.append(resolutions.sorted(by: Self.resolutionOrder)
                .map(WallhavenOptions.resolutionTitle).joined(separator: ", "))
        default: break
        }
        if let color { parts.append("#\(color)") }
        return parts.joined(separator: " · ")
    }

    var hasCustomFilters: Bool { resettingFilters() != self }

    fileprivate static func bits<T: Hashable>(_ value: String?, _ cases: [T]) -> Set<T>? {
        guard let value, value.count == cases.count, value.allSatisfy({ $0 == "0" || $0 == "1" })
        else { return nil }
        let set = Set(zip(value, cases).filter { $0.0 == "1" }.map(\.1))
        return set.isEmpty ? nil : set
    }

    fileprivate static func bitString<T: Hashable>(_ set: Set<T>, _ cases: [T]) -> String {
        String(cases.map { set.contains($0) ? "1" : "0" })
    }

    private static func list(_ value: String?) -> Set<String> {
        Set((value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    static func resolutionOrder(_ a: String, _ b: String) -> Bool {
        let all = WallhavenOptions.resolutions
        return (all.firstIndex(of: a) ?? .max, a) < (all.firstIndex(of: b) ?? .max, b)
    }
}

struct WallhavenPage: Codable, Sendable {
    var items: [WallpaperItem]
    var currentPage: Int
    var lastPage: Int
    var seed: String?
    var failedPreviews: Int = 0
}

enum WallhavenError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited
    case http(Int)
    case invalidResponse
    case invalidImage
    case invalidAPIKey
    case previewsUnavailable

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Wallhaven API Key 无效，请在设置中更新或移除。"
        case .rateLimited: "Wallhaven 请求过于频繁，请稍后再试。"
        case .http(let status): "Wallhaven 请求失败（HTTP \(status)）。"
        case .invalidResponse: "Wallhaven 返回了无效数据，请稍后再试。"
        case .invalidImage: "Wallhaven 图片下载失败或图片格式无效。"
        case .invalidAPIKey: "API Key 包含无效字符，请重新粘贴。"
        case .previewsUnavailable: "Wallhaven 预览图下载失败，请稍后重试。"
        }
    }
}

struct WallhavenService: Sendable {
    let directory: URL
    let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        directory: URL = StorePaths.wallhaven,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await WallhavenNetwork.session.data(for: $0)
        }
    ) {
        self.directory = directory
        self.load = load
    }

    static func searchRequest(
        search: WallhavenSearch, page: Int = 1, seed: String? = nil, apiKey: String = ""
    ) throws -> URLRequest {
        let key = try normalizedAPIKey(apiKey)
        var url = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        // Explicit filters prevent authenticated account defaults from changing the results.
        var items = [
            URLQueryItem(
                name: "q", value: search.query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(
                name: "categories",
                value: WallhavenSearch.bitString(
                    search.effectiveCategories, WallhavenCategory.allCases)),
            URLQueryItem(
                name: "purity",
                value: WallhavenSearch.bitString(
                    search.effectivePurity(hasAPIKey: !key.isEmpty), WallhavenPurity.allCases)),
            URLQueryItem(name: "sorting", value: search.sorting.rawValue),
            URLQueryItem(name: "order", value: search.order.rawValue),
            URLQueryItem(name: "page", value: "\(max(1, page))"),
        ]
        switch search.resolutionMode {
        case .atLeast where WallhavenSearch.isResolution(search.atLeast):
            items.append(URLQueryItem(name: "atleast", value: search.atLeast))
        case .exact where !search.validResolutions.isEmpty:
            items.append(
                URLQueryItem(
                    name: "resolutions",
                    value: search.validResolutions.sorted(by: WallhavenSearch.resolutionOrder)
                        .joined(separator: ",")))
        default: break
        }
        let ratios = WallhavenOptions.ratios.filter(search.ratios.contains)
            + search.ratios.filter { !WallhavenOptions.ratios.contains($0) && WallhavenSearch.isRatio($0) }.sorted()
        if !ratios.isEmpty {
            items.append(URLQueryItem(name: "ratios", value: ratios.joined(separator: ",")))
        }
        if let color = search.color, WallhavenSearch.isColor(color) {
            items.append(URLQueryItem(name: "colors", value: color))
        }
        if search.sorting == .toplist {
            items.append(URLQueryItem(name: "topRange", value: search.topRange.rawValue))
        }
        if search.sorting == .random, let seed, !seed.isEmpty {
            items.append(URLQueryItem(name: "seed", value: seed))
        }
        url.queryItems = items
        var request = URLRequest(
            url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-API-Key") }
        return request
    }

    static func normalizedAPIKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw WallhavenError.invalidAPIKey
        }
        return key
    }

    func fetch(
        search: WallhavenSearch, page: Int = 1, seed: String? = nil, apiKey: String = ""
    ) async throws -> WallhavenPage {
        let request = try Self.searchRequest(search: search, page: page, seed: seed, apiKey: apiKey)
        let (data, response) = try await load(request)
        try Self.validate(response)
        let result: SearchResponse
        do {
            result = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw WallhavenError.invalidResponse
        }
        let hasAPIKey = !(try Self.normalizedAPIKey(apiKey)).isEmpty
        let photos = result.data.filter { search.accepts($0, hasAPIKey: hasAPIKey) }
        // Keep the API order while bounding thumbnail traffic to four concurrent downloads.
        let downloaded = await withTaskGroup(of: (Int, WallpaperItem?).self) { group in
            var next = 0
            var items: [(Int, WallpaperItem?)] = []
            func enqueue(_ index: Int) {
                group.addTask { (index, try? await self.preview(photos[index])) }
            }
            while next < min(4, photos.count) {
                enqueue(next)
                next += 1
            }
            for await item in group {
                items.append(item)
                if next < photos.count {
                    enqueue(next)
                    next += 1
                }
            }
            return items.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        try Task.checkCancellation()
        if !photos.isEmpty && downloaded.isEmpty { throw WallhavenError.previewsUnavailable }
        let batch = WallhavenPage(
            items: downloaded, currentPage: max(1, result.meta.current_page),
            lastPage: max(1, result.meta.last_page), seed: result.meta.seed,
            failedPreviews: photos.count - downloaded.count
        )
        try save(CachedSearch(search: search, page: batch))
        return batch
    }

    func cachedPage(for search: WallhavenSearch) -> WallhavenPage? {
        guard var cache = cachedSearch(), cache.search == search else { return nil }
        cache.page.items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        return cache.page
    }

    func fullWallpaper(for item: WallpaperItem) async throws -> (URL, WallpaperItem) {
        if let local = item.fullLocalURL, FileManager.default.fileExists(atPath: local.path) {
            return (local, item)
        }
        guard item.onlineSource == .wallhaven, let remote = item.fullResolutionURL else {
            throw WallhavenError.invalidImage
        }
        let id = String(item.id.dropFirst("wallhaven:".count))
        try Self.validateID(id)
        try Self.validateMediaURL(remote, host: "w.wallhaven.cc")
        guard ["jpg", "jpeg", "png", "webp"].contains(remote.pathExtension.lowercased()) else {
            throw WallhavenError.invalidImage
        }
        let destination = directory.appendingPathComponent("Full")
            .appendingPathComponent("wallhaven-\(id).\(remote.pathExtension.lowercased())")
        try await download(remote, to: destination)
        var updated = item
        updated.fullLocalURL = destination
        if var cache = cachedSearch(),
            let index = cache.page.items.firstIndex(where: { $0.id == item.id })
        {
            cache.page.items[index] = updated
            try save(cache)
        }
        return (destination, updated)
    }

    private func preview(_ photo: Photo) async throws -> WallpaperItem {
        try Self.validateID(photo.id)
        try Self.validateMediaURL(photo.thumbs.large, host: "th.wallhaven.cc")
        try Self.validateMediaURL(photo.path, host: "w.wallhaven.cc")
        let destination = directory.appendingPathComponent("Previews")
            .appendingPathComponent("wallhaven-\(photo.id).jpg")
        try await download(photo.thumbs.large, to: destination)
        let original = directory.appendingPathComponent("Full")
            .appendingPathComponent(
                "wallhaven-\(photo.id).\(photo.path.pathExtension.lowercased())")
        return WallpaperItem(
            id: "wallhaven:\(photo.id)", url: destination,
            title: "Wallhaven \(photo.id) · \(photo.dimension_x)×\(photo.dimension_y)",
            kind: .wallhaven, source: "Wallhaven", fullResolutionURL: photo.path,
            fullLocalURL: FileManager.default.fileExists(atPath: original.path) ? original : nil,
            previewRemoteURL: photo.thumbs.large
        )
    }

    private func download(_ url: URL, to destination: URL) async throws {
        if let data = try? Data(contentsOf: destination), Self.isImage(data) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: destination.path)
            return
        }
        let (data, response) = try await load(URLRequest(url: url, timeoutInterval: 60))
        try Self.validate(response)
        guard Self.isImage(data) else { throw WallhavenError.invalidImage }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(image) > 0
            && CGImageSourceGetStatus(image) == .statusComplete
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw WallhavenError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw WallhavenError.unauthorized
        case 429: throw WallhavenError.rateLimited
        default: throw WallhavenError.http(http.statusCode)
        }
    }

    private static func validateID(_ id: String) throws {
        guard id.utf8.count == 6,
            id.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) })
        else {
            throw WallhavenError.invalidResponse
        }
    }

    private static func validateMediaURL(_ url: URL, host: String) throws {
        guard url.scheme == "https", url.host == host, url.user == nil, url.password == nil,
            url.port == nil || url.port == 443
        else {
            throw WallhavenError.invalidImage
        }
    }

    private var metadataURL: URL { directory.appendingPathComponent("metadata.json") }

    private func cachedSearch() -> CachedSearch? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(CachedSearch.self, from: data)
    }

    private func save(_ cache: CachedSearch) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: metadataURL, options: .atomic)
    }

    private struct CachedSearch: Codable {
        var search: WallhavenSearch
        var page: WallhavenPage
    }

    private struct SearchResponse: Decodable {
        var data: [Photo]
        var meta: Meta
        struct Meta: Decodable {
            var current_page: Int
            var last_page: Int
            var seed: String?
        }
    }

    fileprivate struct Photo: Decodable, Sendable {
        var id: String
        var category: String
        var purity: String
        var dimension_x: Int
        var dimension_y: Int
        var path: URL
        var thumbs: Thumbnails
        struct Thumbnails: Decodable, Sendable { var large: URL }
    }
}

extension WallhavenSearch {
    /// An empty selection would match nothing, so it falls back to every category.
    var effectiveCategories: Set<WallhavenCategory> {
        categories.isEmpty ? Set(WallhavenCategory.allCases) : categories
    }

    /// NSFW needs an API key; without one, or with nothing selected, results stay SFW.
    func effectivePurity(hasAPIKey: Bool) -> Set<WallhavenPurity> {
        let allowed = hasAPIKey ? purity : purity.subtracting([.nsfw])
        return allowed.isEmpty ? [.sfw] : allowed
    }

    var validResolutions: Set<String> { resolutions.filter(Self.isResolution) }

    // Account defaults may override request filters, so purity, category and size are
    // checked again locally. Aspect ratios are left to the API except for orientation.
    fileprivate func accepts(_ photo: WallhavenService.Photo, hasAPIKey: Bool) -> Bool {
        guard let purity = WallhavenPurity(rawValue: photo.purity),
            effectivePurity(hasAPIKey: hasAPIKey).contains(purity),
            let category = WallhavenCategory(rawValue: photo.category),
            effectiveCategories.contains(category)
        else { return false }
        let width = photo.dimension_x
        let height = photo.dimension_y
        switch resolutionMode {
        case .atLeast:
            if let minimum = Self.size(atLeast), width < minimum.0 || height < minimum.1 {
                return false
            }
        case .exact:
            let exact = validResolutions
            if !exact.isEmpty, !exact.contains("\(width)x\(height)") { return false }
        }
        if ratios == ["landscape"] { return width > height }
        if ratios == ["portrait"] { return height > width }
        return true
    }

    private static func size(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 && isResolution(value) ? (parts[0], parts[1]) : nil
    }
}

final class WallhavenNetwork: NSObject, URLSessionTaskDelegate, Sendable {
    static let session = URLSession(
        configuration: .ephemeral, delegate: WallhavenNetwork(), delegateQueue: nil)

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Never forward an API key to another host or downgrade to HTTP.
        guard Self.canRedirect(from: task.originalRequest?.url, to: request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    static func canRedirect(from original: URL?, to target: URL?) -> Bool {
        guard let original, let target else { return false }
        return target.scheme == "https" && target.host == original.host
            && (target.port ?? 443) == (original.port ?? 443)
            && target.user == nil && target.password == nil
    }
}
