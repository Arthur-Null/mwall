import Foundation

actor PaletteService {
    static let shared = PaletteService()
    private struct Key: Hashable {
        let path: String
        let modified: Date?
        let size: Int?
        let style: PaletteStyle
    }
    private var cache: [Key: TerminalPalettePair] = [:]

    func generate(from url: URL, style: PaletteStyle, folders: [LocalFolderBookmark] = []) throws
        -> TerminalPalettePair
    {
        try Task.checkCancellation()
        return try SecurityScopedBookmarks.withAccess(for: url, folders: folders) {
            // URL.resourceValues can retain cached metadata on a reused URL value.
            // Read fresh filesystem attributes so replacing an image invalidates the palette.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let key = Key(
                path: url.standardizedFileURL.path,
                modified: attributes[.modificationDate] as? Date,
                size: attributes[.size] as? Int,
                style: style
            )
            if let cached = cache[key] { return cached }
            let pair = try PaletteGenerator.generate(from: url, style: style)
            try Task.checkCancellation()
            if cache.count >= 24 { cache.removeAll(keepingCapacity: true) }
            cache[key] = pair
            return pair
        }
    }
}
