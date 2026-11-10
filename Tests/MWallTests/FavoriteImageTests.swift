import AppKit
import Foundation
import Testing
@testable import MWall

private func favoriteFixture() throws -> (URL, WallpaperItem) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWallFavoriteTests-\(UUID().uuidString)")
    let cache = root.appendingPathComponent("Cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let image = cache.appendingPathComponent("preview.png")
    try favoritePNG().write(to: image)
    return (root, WallpaperItem(
        id: "wallhaven:abc123", url: image, kind: .wallhaven,
        fullResolutionURL: URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png")))
}

private func favoritePNG() throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

@MainActor
@Test func favoriteThumbnailSurvivesProviderCacheCleanupAndRelaunch() throws {
    let (root, item) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = FavoriteImageStore(directory: root.appendingPathComponent("Favorites"))
    let store = AppStore(previewItems: [item], favoriteImageStore: images)
    store.toggleFavorite(item)
    let saved = try #require(store.favorites.first)
    #expect(saved.url == item.url)
    #expect(saved.fullResolutionURL == item.fullResolutionURL)
    #expect(saved.thumbnailURL?.deletingLastPathComponent().path == images.directory.path)
    let persisted = try JSONEncoder().encode(store.favorites)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: item.url.path)
    try Data(repeating: 0, count: 2 * 1024 * 1024).write(
        to: item.url.deletingLastPathComponent().appendingPathComponent("new-full.jpg"))
    _ = try CacheManager.cleanupCache(in: item.url.deletingLastPathComponent(), limitMB: 1)
    #expect(!FileManager.default.fileExists(atPath: item.url.path))
    let reloaded = try JSONDecoder().decode([WallpaperItem].self, from: persisted)
    #expect(NSImage(contentsOf: reloaded[0].displayThumbnailURL) != nil)
    store.toggleFavorite(saved)
    #expect(store.favorites.isEmpty)
}

@Test func favoriteMigrationUsesOriginalWhenPreviewIsMissing() throws {
    let (root, original) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    var item = original
    item.fullLocalURL = original.url
    item.url = root.appendingPathComponent("missing.jpg")
    #expect(item.displayThumbnailURL == original.url)
    let service = FavoriteImageStore(directory: root.appendingPathComponent("Favorites"))
    let updated = try #require(try service.preserveLocal(item))
    #expect(updated.url == item.url && updated.fullLocalURL == original.url)
    #expect(NSImage(contentsOf: updated.displayThumbnailURL) != nil)
}

@Test func favoriteLegacyJSONStillDecodes() throws {
    let data = Data(#"{"id":"unsplash:abc","url":"file:///missing.jpg","title":"old","kind":"favorite","fullResolutionURL":"https://images.unsplash.com/photo-123?ixid=keep"}"#.utf8)
    let item = try JSONDecoder().decode(WallpaperItem.self, from: data)
    #expect(item.thumbnailURL == nil && item.previewRemoteURL == nil)
    let remote = try #require(FavoriteImageStore.remotePreviewURL(for: item))
    let query = URLComponents(url: remote, resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.contains(URLQueryItem(name: "ixid", value: "keep")) == true)
    #expect(query?.contains(URLQueryItem(name: "w", value: "800")) == true)
}

@Test func favoriteRecoversMissingWallhavenPreviewWithoutAnAPIKey() async throws {
    let (root, original) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: original.url)
    let data = try favoritePNG()
    let service = FavoriteImageStore(directory: root.appendingPathComponent("Favorites")) { request in
        #expect(request.url?.absoluteString == "https://th.wallhaven.cc/lg/ab/abc123.jpg")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let recovered = try await service.recover(original)
    #expect(NSImage(contentsOf: recovered.displayThumbnailURL) != nil)
    #expect(recovered.url == original.url)
    let offline = FavoriteImageStore(directory: service.directory) { _ in
        Issue.record("A durable thumbnail must not require another download")
        throw URLError(.notConnectedToInternet)
    }
    #expect(try await offline.recover(original).thumbnailURL == recovered.thumbnailURL)
}

@Test func favoriteRecoveryRejectsInvalidResponsesAndCanRetry() async throws {
    let (root, item) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: item.url)
    let service = FavoriteImageStore(directory: root.appendingPathComponent("Favorites")) { request in
        (Data("<html>error</html>".utf8),
         HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await #expect(throws: CocoaError.self) { try await service.recover(item) }
    #expect(try service.preserveLocal(item) == nil)
    #expect(!FileManager.default.fileExists(atPath: service.directory.path))
}

@Test func favoriteRemoteRecoveryRestrictsHostsAndIdentifiers() {
    var item = WallpaperItem(
        id: "unsplash:x", url: URL(fileURLWithPath: "/missing"), kind: .favorite,
        fullResolutionURL: URL(string: "https://example.com/private"))
    #expect(FavoriteImageStore.remotePreviewURL(for: item) == nil)
    item.fullResolutionURL = URL(string: "http://images.unsplash.com/photo-x")
    #expect(FavoriteImageStore.remotePreviewURL(for: item) == nil)
    item.id = "wallhaven:../bad"
    #expect(FavoriteImageStore.remotePreviewURL(for: item) == nil)
}

private actor FavoriteDownloadGate {
    var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            started = true
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Test func favoriteRemovedDuringRecoveryIsNotResurrected() async throws {
    let (root, item) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: item.url)
    let data = try favoritePNG()
    let gate = FavoriteDownloadGate()
    let images = FavoriteImageStore(directory: root.appendingPathComponent("Favorites")) { request in
        await gate.wait()
        return (data, HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let store = AppStore(previewItems: [item], favoriteImageStore: images)
    store.toggleFavorite(item)
    for _ in 0..<1000 {
        if await gate.started { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let started = await gate.started
    #expect(started)
    store.toggleFavorite(item)
    await gate.finish()
    try await Task.sleep(for: .milliseconds(20))
    #expect(store.favorites.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: images.directory.path))
}

@MainActor
@Test func favoriteLocalOriginalNeverBecomesThumbnailWhenApplied() async throws {
    let (root, original) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    var item = original
    item.id = item.url.path
    item.kind = .local
    item.fullResolutionURL = nil
    let store = AppStore(
        previewItems: [item],
        favoriteImageStore: FavoriteImageStore(directory: root.appendingPathComponent("Favorites")))
    store.toggleFavorite(item)
    let saved = try #require(store.favorites.first)
    #expect(saved.thumbnailURL != item.url)
    #expect(try await store.resolveOriginal(saved) == item.url)
}
@MainActor
@Test func favoritePreviewIndicatorTracksAvailableOriginal() throws {
    let (root, original) = try favoriteFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let images = FavoriteImageStore(directory: root.appendingPathComponent("Favorites"))
    var favorite = try #require(try images.preserveLocal(original))
    favorite.kind = .favorite
    let preview = AppStore(
        previewItems: [], favoriteImageStore: images, previewFavorites: [favorite])
    preview.selectWallpaper(favorite)
    #expect(preview.usesThumbnailPreview)

    favorite.fullLocalURL = original.url
    let downloaded = AppStore(
        previewItems: [], favoriteImageStore: images, previewFavorites: [favorite])
    downloaded.selectWallpaper(favorite)
    #expect(!downloaded.usesThumbnailPreview)

    try FileManager.default.removeItem(at: original.url)
    #expect(downloaded.usesThumbnailPreview)
}
