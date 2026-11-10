import CryptoKit
import Foundation
import ImageIO

/// Favorite thumbnails are user data, not disposable provider caches.
struct FavoriteImageStore: Sendable {
    let directory: URL
    let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        directory: URL = StorePaths.favoriteImages,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.directory = directory
        self.load = load
    }

    func preserveLocal(_ item: WallpaperItem) throws -> WallpaperItem? {
        let destination = destination(for: item)
        if isImage(at: destination) {
            var updated = item
            updated.thumbnailURL = destination
            return updated
        }
        for source in [item.thumbnailURL, item.url, item.fullLocalURL].compactMap({ $0 }) {
            guard source.isFileURL,
                let data = try? Data(contentsOf: source),
                let thumbnail = thumbnailData(data)
            else { continue }
            return try save(thumbnail, for: item)
        }
        return nil
    }

    func recover(_ item: WallpaperItem) async throws -> WallpaperItem {
        if let local = try preserveLocal(item) { return local }
        guard let url = Self.remotePreviewURL(for: item) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let (data, response) = try await load(URLRequest(url: url, timeoutInterval: 30))
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            let thumbnail = thumbnailData(data)
        else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        return try save(thumbnail, for: item)
    }

    static func remotePreviewURL(for item: WallpaperItem) -> URL? {
        if item.onlineSource == .wallhaven {
            if let url = item.previewRemoteURL, isAllowed(url, host: "th.wallhaven.cc") {
                return url
            }
            let id = String(item.id.dropFirst("wallhaven:".count))
            guard id.range(of: "^[a-z0-9]{6}$", options: .regularExpression) != nil else {
                return nil
            }
            return URL(string: "https://th.wallhaven.cc/lg/\(id.prefix(2))/\(id).jpg")
        }
        if item.onlineSource == .unsplash,
            let url = item.previewRemoteURL ?? item.fullResolutionURL,
            isAllowed(url, host: "images.unsplash.com"),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            let sizeKeys: Set<String> = ["w", "h", "fit", "crop", "fm", "q"]
            components.queryItems = (components.queryItems ?? []).filter {
                !sizeKeys.contains($0.name)
            } + [
                URLQueryItem(name: "w", value: "800"),
                URLQueryItem(name: "h", value: "450"),
                URLQueryItem(name: "fit", value: "crop"),
                URLQueryItem(name: "fm", value: "jpg"),
                URLQueryItem(name: "q", value: "85"),
            ]
            return components.url
        }
        return nil
    }

    private static func isAllowed(_ url: URL, host: String) -> Bool {
        url.scheme == "https" && url.host == host && url.user == nil
            && url.password == nil && (url.port == nil || url.port == 443)
    }

    private func destination(for item: WallpaperItem) -> URL {
        let digest = SHA256.hash(data: Data(item.id.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    private func isImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
    }

    private func thumbnailData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetStatus(source) == .statusComplete,
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
            ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func save(_ data: Data, for item: WallpaperItem) throws -> WallpaperItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = destination(for: item)
        try data.write(to: url, options: .atomic)
        var updated = item
        updated.thumbnailURL = url
        return updated
    }
}
