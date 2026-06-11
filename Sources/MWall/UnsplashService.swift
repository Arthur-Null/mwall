import Foundation

struct UnsplashDownloadResult {
    var item: WallpaperItem
    var author: String
}

enum UnsplashService {
    static func downloadRandom(accessKey: String, query: String) async throws -> UnsplashDownloadResult {
        let trimmedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "MWall.Unsplash", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先填写 Unsplash Access Key"])
        }

        var components = URLComponents(string: "https://api.unsplash.com/photos/random")!
        components.queryItems = [
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "content_filter", value: "high")
        ]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "query", value: trimmedQuery))
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Client-ID \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        let photo = try JSONDecoder().decode(UnsplashPhoto.self, from: data)

        try? await trackDownload(photo: photo, accessKey: trimmedKey)

        let imageURL = imageURL(from: photo)
        let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
        try validateHTTP(imageResponse, data: imageData)

        try FileManager.default.createDirectory(at: StorePaths.unsplash, withIntermediateDirectories: true)
        let filename = safeFilename("\(photo.id)-\(photo.user.username).jpg")
        let destination = StorePaths.unsplash.appendingPathComponent(filename)
        try imageData.write(to: destination, options: [.atomic])

        let title = photo.description ?? photo.altDescription ?? "Unsplash \(photo.id)"
        let item = WallpaperItem(
            url: destination,
            title: title,
            kind: .unsplash,
            source: "Photo by \(photo.user.name)"
        )
        return UnsplashDownloadResult(item: item, author: photo.user.name)
    }

    private static func imageURL(from photo: UnsplashPhoto) -> URL {
        var components = URLComponents(url: photo.urls.raw, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "w", value: "3840"))
        items.append(URLQueryItem(name: "h", value: "2160"))
        items.append(URLQueryItem(name: "fit", value: "crop"))
        items.append(URLQueryItem(name: "crop", value: "entropy"))
        items.append(URLQueryItem(name: "fm", value: "jpg"))
        items.append(URLQueryItem(name: "q", value: "90"))
        components.queryItems = items
        return components.url ?? photo.urls.full
    }

    private static func trackDownload(photo: UnsplashPhoto, accessKey: String) async throws {
        var request = URLRequest(url: photo.links.downloadLocation)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "MWall.Unsplash", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unsplash download tracking failed"])
        }
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

    private static func safeFilename(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(input.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}

private struct UnsplashPhoto: Decodable {
    struct URLs: Decodable {
        var raw: URL
        var full: URL
    }

    struct Links: Decodable {
        var downloadLocation: URL

        enum CodingKeys: String, CodingKey {
            case downloadLocation = "download_location"
        }
    }

    struct User: Decodable {
        var name: String
        var username: String
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
