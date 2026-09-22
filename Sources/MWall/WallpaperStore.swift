import Foundation

enum WallpaperStore {
    static var systemIndexURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
    }

    static func updateSystemIndex(imageURL: URL) throws -> Int {
        try updateIndex(at: systemIndexURL, imageURL: imageURL)
    }

    static func updateIndex(at indexURL: URL, imageURL: URL) throws -> Int {
        let originalData = try Data(contentsOf: indexURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(
            from: originalData,
            options: [.mutableContainersAndLeaves],
            format: &format
        )
        guard let root = plist as? NSMutableDictionary else {
            throw NSError(domain: "MWall.WallpaperStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "壁纸配置不是可写 plist 字典"])
        }

        let configuration = try imageConfigurationData(for: imageURL)
        let updatedCount = updateDesktopNodes(in: root, imageURL: imageURL, configuration: configuration)
        guard updatedCount > 0 else {
            throw NSError(domain: "MWall.WallpaperStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "没有找到可更新的桌面配置"])
        }

        let outputFormat: PropertyListSerialization.PropertyListFormat = format == .xml ? .xml : .binary
        let updatedData = try PropertyListSerialization.data(fromPropertyList: root, format: outputFormat, options: 0)
        let temporaryURL = indexURL.deletingLastPathComponent()
            .appendingPathComponent(".\(indexURL.lastPathComponent).mwall-\(UUID().uuidString)")
        try updatedData.write(to: temporaryURL, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temporaryURL)
        return updatedCount
    }

    private static func updateDesktopNodes(in value: Any, imageURL: URL, configuration: Data) -> Int {
        var count = 0
        if let dictionary = value as? NSMutableDictionary {
            if let desktop = dictionary["Desktop"] as? NSMutableDictionary {
                updateDesktop(desktop, imageURL: imageURL, configuration: configuration)
                count += 1
            }
            for nestedValue in dictionary.allValues {
                count += updateDesktopNodes(in: nestedValue, imageURL: imageURL, configuration: configuration)
            }
        } else if let array = value as? NSMutableArray {
            for nestedValue in array {
                count += updateDesktopNodes(in: nestedValue, imageURL: imageURL, configuration: configuration)
            }
        }
        return count
    }

    private static func updateDesktop(_ desktop: NSMutableDictionary, imageURL: URL, configuration: Data) {
        let content = desktop["Content"] as? NSMutableDictionary ?? NSMutableDictionary()
        let choices = content["Choices"] as? NSMutableArray ?? NSMutableArray()
        let choice = (choices.firstObject as? NSMutableDictionary) ?? NSMutableDictionary()
        choice["Configuration"] = configuration
        // Keep Files empty. Writing `[{ relative = file:///... }]` matches older docs but on
        // current macOS it prevents WallpaperAgent from opening the image, so the desktop
        // path updates while the pixels stay stuck / Settings shows a missing preview.
        choice["Files"] = NSMutableArray()
        choice["Provider"] = "com.apple.wallpaper.choice.image"
        if choices.count == 0 {
            choices.add(choice)
        } else {
            choices.replaceObject(at: 0, with: choice)
        }
        content["Choices"] = choices
        if content["Shuffle"] == nil {
            content["Shuffle"] = "$null"
        }
        desktop["Content"] = content
        desktop["LastSet"] = Date()
        desktop["LastUse"] = Date()
    }

    private static func imageConfigurationData(for imageURL: URL) throws -> Data {
        let configuration: [String: Any] = [
            "type": "imageFile",
            "url": [
                "relative": imageURL.absoluteString
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: configuration, format: .binary, options: 0)
    }
}
