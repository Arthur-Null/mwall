import CoreGraphics
import Foundation
import ImageIO
import Security
import Testing

@testable import MWall

@Test func wallhavenRequestUsesExplicitSafeDefaultsAndOptionalHeader() throws {
    let guest = try WallhavenService.searchRequest(search: WallhavenSearch())
    let parameters = queryValues(guest)
    #expect(parameters["categories"] == "010")
    #expect(parameters["purity"] == "100")
    #expect(parameters["atleast"] == "1920x1080")
    #expect(parameters["ratios"] == "landscape")
    #expect(parameters["sorting"] == "random")
    #expect(parameters["page"] == "1")
    #expect(guest.value(forHTTPHeaderField: "X-API-Key") == nil)
    let keyed = try WallhavenService.searchRequest(
        search: WallhavenSearch(query: "anime & sky + id:1"), apiKey: " fixture-secret \n")
    #expect(keyed.value(forHTTPHeaderField: "X-API-Key") == "fixture-secret")
    #expect(!keyed.url!.absoluteString.contains("fixture-secret"))
    #expect(queryValues(keyed)["q"] == "anime & sky + id:1")
    #expect(queryValues(keyed)["purity"] == "100")
    #expect(throws: WallhavenError.invalidAPIKey) {
        try WallhavenService.searchRequest(
            search: WallhavenSearch(), apiKey: "x\r\nX-Header: injected")
    }
}

@Test func wallhavenPaginationKeepsRandomSeedOnlyForRandomSorting() throws {
    let random = try WallhavenService.searchRequest(
        search: WallhavenSearch(), page: 2, seed: "ABC123")
    #expect(queryValues(random)["seed"] == "ABC123")
    #expect(queryValues(random)["page"] == "2")
    let popular = try WallhavenService.searchRequest(
        search: WallhavenSearch(category: .all, sorting: .toplist), page: 0, seed: "ABC123")
    #expect(queryValues(popular)["seed"] == nil)
    #expect(queryValues(popular)["categories"] == "111")
    #expect(queryValues(popular)["topRange"] == "1M")
    #expect(queryValues(popular)["page"] == "1")
}

@Test func wallhavenSettingsAreBackwardCompatibleAndContainNoCredentials() throws {
    var settings = try JSONDecoder().decode(
        AppSettings.self,
        from: Data(#"{"currentSource":"unsplash","unsplashAccessKey":"legacy"}"#.utf8)
    )
    #expect(settings.currentSource == .unsplash && settings.unsplashAccessKey == "legacy")
    #expect(settings.wallhavenSearch == WallhavenSearch())
    #expect(settings.wallhavenCacheLimitMB == 600)
    settings.currentSource = .wallhaven
    settings.wallhavenSearch = WallhavenSearch(
        query: "mountain", category: .general, sorting: .latest)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    #expect(!String(decoding: data, as: UTF8.self).contains("wallhavenAPIKey"))
}

@Test func wallhavenCachesPreviewsAndOriginalsWithoutLeakingKeys() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(body: responseBody())
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch(), apiKey: "fixture-secret")
    let item = try #require(batch.items.first)
    #expect(item.onlineSource == .wallhaven)
    #expect(batch.currentPage == 1 && batch.lastPage == 3 && batch.seed == "ABC123")
    #expect(FileManager.default.fileExists(atPath: item.url.path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Full").path))
    #expect(service.cachedPage(for: WallhavenSearch())?.items == batch.items)
    #expect(service.cachedPage(for: WallhavenSearch(query: "other")) == nil)
    let (full, updated) = try await service.fullWallpaper(for: item)
    #expect(full.pathExtension == "png" && updated.fullLocalURL == full)
    #expect(service.cachedPage(for: WallhavenSearch())?.items.first?.fullLocalURL == full)
    _ = try await service.fullWallpaper(for: item)
    _ = try await service.fetch(search: WallhavenSearch(), apiKey: "fixture-secret")
    #expect(service.cachedPage(for: WallhavenSearch())?.items.first?.fullLocalURL == full)
    let requests = await mock.requests
    #expect(requests.count == 4)  // Two API calls, one preview, one original.
    #expect(
        requests.filter { $0.url?.host != "wallhaven.cc" }.allSatisfy {
            $0.value(forHTTPHeaderField: "X-API-Key") == nil
        })
    let metadata = try String(
        contentsOf: root.appendingPathComponent("metadata.json"), encoding: .utf8)
    #expect(!metadata.contains("fixture-secret"))
}

@Test func wallhavenChecksPurityCategoryDimensionsAndPreservesAPIOrder() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let photos = [
        photo("abc123"), photo("def456"), photo("aaa111", purity: "sketchy"),
        photo("bbb222", purity: "nsfw"), photo("ccc333", category: "general"),
        photo("ddd444", width: 1080, height: 1920), photo("eee555", width: 1280, height: 720),
    ]
    let mock = try MockWallhaven(body: responseBody(photos))
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    #expect(batch.items.map(\.id) == ["wallhaven:abc123", "wallhaven:def456"])
    #expect(await mock.requests.count == 3)
}

@Test func wallhavenPartialDownloadsKeepSuccessfulResults() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(
        body: responseBody([photo("abc123"), photo("def456")]), failures: ["def456.jpg"])
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    #expect(batch.items.count == 1 && batch.failedPreviews == 1)
}

@Test func wallhavenAllFailedPreviewsDoNotReplaceWorkingCache() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let good = try MockWallhaven(body: responseBody())
    let service = WallhavenService(directory: root, load: { try await good.load($0) })
    _ = try await service.fetch(search: WallhavenSearch())
    let bad = try MockWallhaven(body: responseBody([photo("def456")]), failures: ["def456.jpg"])
    let broken = WallhavenService(directory: root, load: { try await bad.load($0) })
    await #expect(throws: WallhavenError.previewsUnavailable) {
        try await broken.fetch(search: WallhavenSearch(query: "new"))
    }
    #expect(service.cachedPage(for: WallhavenSearch())?.items.first?.id == "wallhaven:abc123")
}

@Test(arguments: [401, 403, 429, 500])
func wallhavenHTTPErrorsAreActionableAndDoNotEchoServerSecrets(status: Int) async throws {
    let root = temporaryCache()
    let service = WallhavenService(directory: root) { request in
        (Data("fixture-secret".utf8), httpResponse(request, status: status))
    }
    let expected: WallhavenError =
        status == 401 ? .unauthorized : (status == 429 ? .rateLimited : .http(status))
    await #expect(throws: expected) {
        try await service.fetch(search: WallhavenSearch(), apiKey: "fixture-secret")
    }
    #expect(!expected.localizedDescription.contains("fixture-secret"))
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func wallhavenEmptyResultsAndMalformedResponses() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(body: responseBody([]))
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    #expect(batch.items.isEmpty)
    let broken = WallhavenService(directory: root) { request in
        (Data("<html>unavailable</html>".utf8), httpResponse(request))
    }
    await #expect(throws: WallhavenError.invalidResponse) {
        try await broken.fetch(search: WallhavenSearch())
    }
    let offline = WallhavenService(directory: root) { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: URLError.self) { try await offline.fetch(search: WallhavenSearch()) }
    #expect(service.cachedPage(for: WallhavenSearch()) != nil)
}

@Test func wallhavenRejectsUnsafeImageURLsAndFilenames() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = WallhavenService(directory: root) { _ in
        Issue.record("Unsafe image must not reach the transport")
        throw WallhavenError.invalidImage
    }
    var item = WallpaperItem(
        id: "wallhaven:abc123", url: root, kind: .wallhaven,
        fullResolutionURL: URL(string: "https://untrusted.example/image.png")!)
    await #expect(throws: WallhavenError.invalidImage) {
        try await service.fullWallpaper(for: item)
    }
    item.id = "wallhaven:../bad"
    item.fullResolutionURL = URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png")!
    await #expect(throws: WallhavenError.invalidResponse) {
        try await service.fullWallpaper(for: item)
    }
}

@Test func wallhavenRejectsHTMLDisguisedAsAnImage() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = WallhavenService(directory: root) { request in
        (Data("<html>error</html>".utf8), httpResponse(request))
    }
    let item = WallpaperItem(
        id: "wallhaven:abc123", url: root, kind: .wallhaven,
        fullResolutionURL: URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png")!)
    await #expect(throws: WallhavenError.invalidImage) {
        try await service.fullWallpaper(for: item)
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Full").path))
}

@Test func wallhavenDoesNotForwardKeysAcrossRedirectOrigins() {
    let original = URL(string: "https://wallhaven.cc/api/v1/search")!
    #expect(
        WallhavenNetwork.canRedirect(
            from: original, to: URL(string: "https://wallhaven.cc/api/v1/search?q=sky")))
    for value in [
        "https://other.example/api", "http://wallhaven.cc/api",
        "https://wallhaven.cc:8443/api", "https://user@wallhaven.cc/api",
    ] {
        #expect(!WallhavenNetwork.canRedirect(from: original, to: URL(string: value)))
    }
}

@Test func wallhavenMissingAndCorruptPreviewsAreRecovered() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(body: responseBody())
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    let item = try #require(batch.items.first)
    try Data("invalid".utf8).write(to: item.url)
    _ = try await service.fetch(search: WallhavenSearch())
    #expect(await mock.requests.count == 4)
    try FileManager.default.removeItem(at: item.url)
    #expect(service.cachedPage(for: WallhavenSearch())?.items.isEmpty == true)
}

@MainActor @Test func wallhavenFavoritesAndHistoryResolveThroughTheirOriginalProvider() async throws
{
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(body: responseBody())
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    var item = try #require(batch.items.first)
    let store = AppStore(previewItems: batch.items, wallhavenService: service)
    #expect(store.settings.currentSource == .wallhaven)
    #expect(store.currentWallpaper?.id == item.id)
    for kind in [WallpaperKind.favorite, .history] {
        item.kind = kind
        #expect(item.onlineSource == .wallhaven)
        let full = try await store.resolveOriginal(item)
        #expect(full.lastPathComponent == "wallhaven-abc123.png")
    }
    #expect(await mock.requests.count == 3)
    #expect(store.currentWallpaper?.fullLocalURL != nil)
}

@Test func wallhavenCleanupKeepsMetadataAndLeavesOtherSourcesAlone() throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("Wallhaven")
    let other = root.appendingPathComponent("Unsplash.jpg")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let metadata = cache.appendingPathComponent("metadata.json")
    let image = cache.appendingPathComponent("large.png")
    try Data("{}".utf8).write(to: metadata)
    try Data(repeating: 0, count: 2 * 1024 * 1024).write(to: image)
    try Data("untouched".utf8).write(to: other)
    #expect(try CacheManager.cleanupCache(in: cache, limitMB: 1) == 1)
    #expect(FileManager.default.fileExists(atPath: metadata.path))
    #expect(!FileManager.default.fileExists(atPath: image.path))
    #expect(try String(contentsOf: other, encoding: .utf8) == "untouched")
}

@MainActor @Test func wallhavenFailedNewSearchKeepsVisibleResultsAndSelection() async throws {
    let root = temporaryCache()
    let item = WallpaperItem(id: "wallhaven:abc123", url: root, kind: .wallhaven)
    let service = WallhavenService(directory: root) { request in
        (Data(), httpResponse(request, status: 429))
    }
    let store = AppStore(previewItems: [item], wallhavenService: service)
    store.settings.wallhavenSearch.query = "new query"
    store.refreshWallhaven()
    for _ in 0..<100 where store.isWorking {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!store.isWorking)
    #expect(store.visibleWallpapers == [item])
    #expect(store.selectedWallpaperID == item.id)
    #expect(!store.wallhavenResultsMatchSearch)
    #expect(store.lastMessage.contains("仍显示上次搜索结果"))
}

@MainActor @Test func wallhavenHistoryOriginalRecoveryUpdatesPalettePreview() async throws {
    let root = temporaryCache()
    defer { try? FileManager.default.removeItem(at: root) }
    let mock = try MockWallhaven(body: responseBody())
    let service = WallhavenService(directory: root, load: { try await mock.load($0) })
    let batch = try await service.fetch(search: WallhavenSearch())
    var item = try #require(batch.items.first)
    item.fullLocalURL = root.appendingPathComponent("deleted-applied-original.png")
    let store = AppStore(
        previewItems: [], previewHistory: [HistoryEntry(item: item)], wallhavenService: service)
    store.settings.currentSource = .history
    #expect(store.usesThumbnailPreview)
    let full = try await store.resolveOriginal(try #require(store.currentWallpaper))
    #expect(store.wallhavenWallpapers.isEmpty && store.favorites.isEmpty)
    #expect(store.history.first?.item.fullLocalURL == full)
    #expect(store.currentWallpaper?.fullLocalURL == full)
    #expect(!store.usesThumbnailPreview)
}

@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MWALL_WALLHAVEN_LIVE"] != nil,
        "Opt in to a public SFW Wallhaven API and image-download smoke test"))
func wallhavenLiveSmoke() async throws {
    let root = ProcessInfo.processInfo.environment["MWALL_WALLHAVEN_LIVE"]!
    let service = WallhavenService(directory: URL(fileURLWithPath: root))
    let batch = try await service.fetch(search: WallhavenSearch())
    let item = try #require(batch.items.first)
    let (full, _) = try await service.fullWallpaper(for: item)
    #expect(FileManager.default.fileExists(atPath: full.path))
    print("Wallhaven live: \(batch.items.count) previews, original \(full.lastPathComponent)")
}

@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MWALL_WALLHAVEN_KEYCHAIN_TEST"] == "1",
        "Opt in to CRUD in a temporary Keychain using synthetic keys"))
func wallhavenKeychainSmoke() throws {
    let root = temporaryCache()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var created: SecKeychain?
    let password = UUID().uuidString
    // Legacy APIs are used only to isolate the test; production credentials use SecItem APIs.
    let status = password.withCString {
        SecKeychainCreate(
            root.appendingPathComponent("test.keychain").path,
            UInt32(password.utf8.count), $0, false, nil, &created)
    }
    try #require(status == errSecSuccess)
    let keychain = try #require(created)
    defer { _ = SecKeychainDelete(keychain) }
    let service = "MWall.Wallhaven.Tests.\(UUID().uuidString)"
    #expect(!WallhavenCredentials.isStored(service: service, keychain: keychain))
    #expect(try WallhavenCredentials.load(service: service, keychain: keychain).isEmpty)
    try WallhavenCredentials.save(" fixture-key-1\n", service: service, keychain: keychain)
    #expect(WallhavenCredentials.isStored(service: service, keychain: keychain))
    #expect(try WallhavenCredentials.load(service: service, keychain: keychain) == "fixture-key-1")
    try WallhavenCredentials.save("fixture-key-2", service: service, keychain: keychain)
    #expect(try WallhavenCredentials.load(service: service, keychain: keychain) == "fixture-key-2")
    try WallhavenCredentials.remove(service: service, keychain: keychain)
    #expect(!WallhavenCredentials.isStored(service: service, keychain: keychain))
    #expect(try WallhavenCredentials.load(service: service, keychain: keychain).isEmpty)
}

private func temporaryCache() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "mwall-wallhaven-\(UUID().uuidString)")
}

private func queryValues(_ request: URLRequest) -> [String: String] {
    Dictionary(
        uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
}

private func photo(
    _ id: String, purity: String = "sfw", category: String = "anime",
    width: Int = 2560, height: Int = 1440
) -> [String: Any] {
    [
        "id": id, "category": category, "purity": purity,
        "dimension_x": width, "dimension_y": height,
        "path": "https://w.wallhaven.cc/full/ab/wallhaven-\(id).png",
        "thumbs": ["large": "https://th.wallhaven.cc/lg/ab/\(id).jpg"],
    ]
}

private func responseBody(_ photos: [[String: Any]]? = nil) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "data": photos ?? [photo("abc123")],
        "meta": ["current_page": 1, "last_page": 3, "seed": "ABC123"],
    ])
}

private func httpResponse(_ request: URLRequest, status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private actor MockWallhaven {
    let body: Data
    let image: Data
    let failures: Set<String>
    var requests: [URLRequest] = []

    init(body: Data, failures: Set<String> = []) throws {
        self.body = body
        self.failures = failures
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let bytes = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        image = bytes as Data
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        if failures.contains(request.url!.lastPathComponent) { throw URLError(.timedOut) }
        return (request.url?.host == "wallhaven.cc" ? body : image, httpResponse(request))
    }
}
