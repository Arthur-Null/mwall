import Foundation

enum Persistence {
    static func prepareDirectories() {
        let fm = FileManager.default
        [
            StorePaths.appSupport,
            StorePaths.cache,
            StorePaths.builtIns,
            StorePaths.unsplash,
            StorePaths.unsplashPreviews,
            StorePaths.unsplashFull
        ].forEach { url in
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) -> T {
        guard let data = try? Data(contentsOf: url) else {
            return fallback
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return fallback
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder.pretty.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("MWall save failed: \(url.path): \(error)")
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
