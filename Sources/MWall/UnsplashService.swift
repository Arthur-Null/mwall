import Foundation

enum UnsplashService {
    static let preferredPoolSize = 12
    static let batchSize = 30
    private static let maxRandomPage = 50

    static func fetchWallpaperBatch(accessKey: String) async throws -> [WallpaperItem] {
        let trimmedKey = try normalizedAccessKey(accessKey)
        let page = Int.random(in: 1...maxRandomPage)

        var components = URLComponents(string: "https://api.unsplash.com/topics/wallpapers/photos")!
        components.queryItems = [
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "order_by", value: "popular"),
            URLQueryItem(name: "per_page", value: "\(batchSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        let data = try await apiData(from: components.url!, accessKey: trimmedKey)
        let photos = try JSONDecoder().decode([UnsplashPhoto].self, from: data)
        let existingIDs = Set(loadCachedItems().map(\.id))

        var items: [WallpaperItem] = []
        var candidates = 0
        var failures = 0
        for photo in photos where !existingIDs.contains(itemID(for: photo.id)) {
            candidates += 1
            do {
                let item = try await cachePreview(for: photo)
                items.append(item)
            } catch {
                failures += 1
            }
        }

        if items.isEmpty, candidates == 0, !photos.isEmpty {
            throw NSError(domain: "MWall.Unsplash", code: 2, userInfo: [NSLocalizedDescriptionKey: "这一批图片已经在缓存中，请再换一批"])
        }
        if items.isEmpty, failures > 0 {
            throw NSError(domain: "MWall.Unsplash", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsplash 预览图下载失败"])
        }
        return items
    }

    static func localItems() -> [WallpaperItem] {
        loadCachedItems().filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func saveCachedItems(_ items: [WallpaperItem]) {
        Persistence.save(items, to: StorePaths.unsplashMetadata)
    }

    static func fullWallpaperURL(for item: WallpaperItem, accessKey: String) async throws -> (URL, WallpaperItem) {
        if let fullLocalURL = item.fullLocalURL,
           FileManager.default.fileExists(atPath: fullLocalURL.path) {
            return (fullLocalURL, item)
        }

        guard let fullResolutionURL = item.fullResolutionURL else {
            if FileManager.default.fileExists(atPath: item.url.path) {
                return (item.url, item)
            }
            throw NSError(domain: "MWall.Unsplash", code: 3, userInfo: [NSLocalizedDescriptionKey: "缺少 Unsplash 原图地址"])
        }

        let trimmedKey = try normalizedAccessKey(accessKey)
        if let downloadLocation = item.downloadLocation {
            try? await trackDownload(downloadLocation: downloadLocation, accessKey: trimmedKey)
        }

        let imageURL = sizedURL(from: fullResolutionURL, width: 3840, height: 2160, quality: 90)
        let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
        try validateHTTP(imageResponse, data: imageData)

        try FileManager.default.createDirectory(at: StorePaths.unsplashFull, withIntermediateDirectories: true)
        let destination = StorePaths.unsplashFull.appendingPathComponent("\(safeFilename(item.id)).jpg")
        try imageData.write(to: destination, options: [.atomic])

        var updated = item
        updated.fullLocalURL = destination
        updateCachedItem(updated)
        return (destination, updated)
    }

    private static func cachePreview(for photo: UnsplashPhoto) async throws -> WallpaperItem {
        try FileManager.default.createDirectory(at: StorePaths.unsplashPreviews, withIntermediateDirectories: true)

        let destination = StorePaths.unsplashPreviews.appendingPathComponent("\(safeFilename(photo.id)).jpg")
        if !FileManager.default.fileExists(atPath: destination.path) {
            let imageURL = sizedURL(from: photo.urls.raw, width: 600, height: 338, quality: 75)
            let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
            try validateHTTP(imageResponse, data: imageData)
            try imageData.write(to: destination, options: [.atomic])
        }

        return WallpaperItem(
            id: itemID(for: photo.id),
            url: destination,
            title: photo.description ?? photo.altDescription ?? "Unsplash \(photo.id)",
            kind: .unsplash,
            source: "Photo by \(photo.user.name)",
            fullResolutionURL: photo.urls.raw,
            downloadLocation: photo.links.downloadLocation
        )
    }

    private static func apiData(from url: URL, accessKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return data
    }

    private static func trackDownload(downloadLocation: URL, accessKey: String) async throws {
        _ = try await apiData(from: downloadLocation, accessKey: accessKey)
    }

    private static func sizedURL(from rawURL: URL, width: Int, height: Int, quality: Int) -> URL {
        var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "w", value: "\(width)"),
            URLQueryItem(name: "h", value: "\(height)"),
            URLQueryItem(name: "fit", value: "crop"),
            URLQueryItem(name: "crop", value: "entropy"),
            URLQueryItem(name: "fm", value: "jpg"),
            URLQueryItem(name: "q", value: "\(quality)")
        ]
        return components.url ?? rawURL
    }

    private static func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(UnsplashError.self, from: data).errors.joined(separator: ", "))
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "MWall.Unsplash", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func normalizedAccessKey(_ accessKey: String) throws -> String {
        let trimmedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "MWall.Unsplash", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先填写 Unsplash Access Key"])
        }
        return trimmedKey
    }

    private static func loadCachedItems() -> [WallpaperItem] {
        Persistence.load([WallpaperItem].self, from: StorePaths.unsplashMetadata, fallback: [])
    }

    private static func updateCachedItem(_ item: WallpaperItem) {
        var items = loadCachedItems()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        saveCachedItems(items)
    }

    private static func itemID(for photoID: String) -> String {
        "unsplash:\(photoID)"
    }

    private static func safeFilename(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(input.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}

private struct UnsplashPhoto: Decodable {
    struct URLs: Decodable {
        var raw: URL
    }

    struct Links: Decodable {
        var downloadLocation: URL

        enum CodingKeys: String, CodingKey {
            case downloadLocation = "download_location"
        }
    }

    struct User: Decodable {
        var name: String
    }

    var id: String
    var description: String?
    var altDescription: String?
    var urls: URLs
    var links: Links
    var user: User

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case altDescription = "alt_description"
        case urls
        case links
        case user
    }
}

private struct UnsplashError: Decodable {
    var errors: [String]
}
