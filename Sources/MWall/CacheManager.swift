import Foundation

enum CacheManager {
    static func cleanupUnsplashCache(limitMB: Int) throws -> Int {
        try cleanupCache(in: StorePaths.unsplash, limitMB: limitMB)
    }

    static func cleanupCache(in directory: URL, limitMB: Int) throws -> Int {
        let limitBytes = max(1, limitMB) * 1024 * 1024
        let files = try cacheFiles(in: directory)
        let total = files.reduce(0) { $0 + $1.size }
        guard total > limitBytes else {
            return 0
        }

        var removed = 0
        var current = total
        for file in files.sorted(by: { $0.modified < $1.modified }) {
            try FileManager.default.removeItem(at: file.url)
            removed += 1
            current -= file.size
            if current <= limitBytes {
                break
            }
        }
        return removed
    }

    static func unsplashCacheSizeMB() -> Int {
        cacheSizeMB(in: StorePaths.unsplash)
    }

    static func cacheSizeMB(in directory: URL) -> Int {
        let total = (try? cacheFiles(in: directory).reduce(0) { $0 + $1.size }) ?? 0
        return Int((Double(total) / 1024.0 / 1024.0).rounded())
    }

    private struct CacheFile {
        var url: URL
        var size: Int
        var modified: Date
    }

    private static func cacheFiles(in directory: URL) throws -> [CacheFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            return []
        }
        let urls = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        )
        return urls.reduce(into: []) { result, url in
            guard
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
                ]),
                values.isRegularFile == true
            else {
                result.append(contentsOf: (try? cacheFiles(in: url)) ?? [])
                return
            }
            guard url.lastPathComponent != "metadata.json" else {
                return
            }
            result.append(
                CacheFile(
                    url: url, size: values.fileSize ?? 0,
                    modified: values.contentModificationDate ?? .distantPast))
        }
    }

}
