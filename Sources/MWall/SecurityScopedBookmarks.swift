import Foundation

enum SecurityScopedBookmarks {
    static func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            NSLog("MWall bookmark create failed: \(url.path): \(error)")
            return nil
        }
    }

    static func resolve(_ folder: LocalFolderBookmark) -> LocalFolderBookmark {
        guard let data = folder.bookmarkData else {
            return folder
        }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            var resolved = folder
            resolved.url = url
            resolved.isStale = stale
            if stale {
                resolved.bookmarkData = makeBookmark(for: url) ?? data
                resolved.isStale = resolved.bookmarkData == data
            }
            return resolved
        } catch {
            NSLog("MWall bookmark resolve failed: \(folder.url.path): \(error)")
            return folder
        }
    }

    static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    static func withAccess<T>(for itemURL: URL, folders: [LocalFolderBookmark], _ body: () throws -> T) rethrows -> T {
        guard let folder = folders.first(where: { itemURL.standardizedFileURL.path.hasPrefix($0.url.standardizedFileURL.path + "/") }) else {
            return try body()
        }
        return try withAccess(to: folder.url, body)
    }
}
