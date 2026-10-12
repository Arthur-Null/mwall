import Foundation
import ImageIO

enum WallhavenCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case anime, general, people, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: "二次元"
        case .general: "综合"
        case .people: "人物"
        case .all: "全部"
        }
    }
    var parameter: String {
        switch self {
        case .anime: "010"
        case .general: "100"
        case .people: "001"
        case .all: "111"
        }
    }
}

enum WallhavenSorting: String, Codable, CaseIterable, Identifiable, Sendable {
    case random
    case latest = "date_added"
    case toplist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .random: "随机"
        case .latest: "最新"
        case .toplist: "热门"
        }
    }
}

struct WallhavenSearch: Codable, Equatable, Sendable {
    var query = ""
    var category: WallhavenCategory = .anime
    var sorting: WallhavenSorting = .random
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
        var url = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        url.queryItems = [
            URLQueryItem(
                name: "q", value: search.query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "categories", value: search.category.parameter),
            // Explicit filters prevent authenticated account defaults from changing the results.
            URLQueryItem(name: "purity", value: "100"),
            URLQueryItem(name: "ratios", value: "landscape"),
            URLQueryItem(name: "atleast", value: "1920x1080"),
            URLQueryItem(name: "sorting", value: search.sorting.rawValue),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "page", value: "\(max(1, page))"),
        ]
        if search.sorting == .toplist {
            url.queryItems?.append(URLQueryItem(name: "topRange", value: "1M"))
        }
        if search.sorting == .random, let seed, !seed.isEmpty {
            url.queryItems?.append(URLQueryItem(name: "seed", value: seed))
        }
        var request = URLRequest(
            url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = try normalizedAPIKey(apiKey)
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
        let photos = result.data.filter {
            $0.purity == "sfw" && $0.dimension_x >= 1920 && $0.dimension_y >= 1080
                && $0.dimension_x > $0.dimension_y
                && (search.category == .all || $0.category == search.category.rawValue)
        }
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
            fullLocalURL: FileManager.default.fileExists(atPath: original.path) ? original : nil
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

    private struct Photo: Decodable, Sendable {
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
