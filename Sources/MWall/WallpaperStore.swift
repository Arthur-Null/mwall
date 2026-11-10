import Foundation

enum WallpaperStore {
    static var systemIndexURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
    }

    static func updateSystemIndex(
        imageURL: URL, screenSaverModuleURL: URL? = nil, updateDesktopImages: Bool = true
    ) throws -> Int {
        try updateIndex(at: systemIndexURL, imageURL: imageURL,
                        screenSaverModuleURL: screenSaverModuleURL, updateDesktopImages: updateDesktopImages)
    }

    static func updateIndex(
        at indexURL: URL, imageURL: URL, screenSaverModuleURL: URL? = nil,
        updateDesktopImages: Bool = true
    ) throws -> Int {
        let originalData = try Data(contentsOf: indexURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(
            from: originalData, options: [], format: &format
        ) as? [String: Any] else {
            throw NSError(domain: "MWall.WallpaperStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "壁纸配置不是 plist 字典"])
        }

        let imageConfiguration = try configurationData([
            "type": "imageFile", "url": ["relative": imageURL.absoluteString]
        ])
        let saverConfiguration = try screenSaverModuleURL.map {
            try configurationData(["module": ["relative": $0.absoluteString]])
        }
        let (updatedRoot, count) = updateNodes(
            root, imageConfiguration: imageConfiguration, saverConfiguration: saverConfiguration,
            updateDesktopImages: updateDesktopImages)
        guard count > 0 else {
            throw NSError(domain: "MWall.WallpaperStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "没有找到可更新的桌面配置"])
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: updatedRoot, format: format == .xml ? .xml : .binary, options: 0)
        let temporaryURL = indexURL.deletingLastPathComponent()
            .appendingPathComponent(".\(indexURL.lastPathComponent).mwall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temporaryURL)
        return count
    }

    private static func updateNodes(
        _ value: Any, imageConfiguration: Data, saverConfiguration: Data?,
        updateDesktopImages: Bool
    ) -> (Any, Int) {
        if var dictionary = value as? [String: Any] {
            let linked = dictionary["Linked"] as? [String: Any]
            let desktop = dictionary["Desktop"] as? [String: Any]
            let idle = dictionary["Idle"] as? [String: Any]
            if linked != nil || desktop != nil || (saverConfiguration != nil && idle != nil) {
                if let saverConfiguration {
                    // A static image in Linked/automatic mode can fall back to an aerial
                    // screen saver. Select the Photos module explicitly in an Idle node.
                    if var desktop = linked ?? desktop {
                        if updateDesktopImages {
                            desktop = updatedNode(desktop, configuration: imageConfiguration,
                                                  provider: "com.apple.wallpaper.choice.image")
                        }
                        dictionary["Desktop"] = desktop
                        dictionary["Type"] = "individual"
                    } else {
                        dictionary["Type"] = "idle"
                    }
                    dictionary["Idle"] = updatedNode(
                        idle ?? [:], configuration: saverConfiguration,
                        provider: "com.apple.wallpaper.choice.screen-saver")
                    dictionary.removeValue(forKey: "Linked")
                } else if updateDesktopImages {
                    let key = linked == nil ? "Desktop" : "Linked"
                    dictionary[key] = updatedNode(
                        linked ?? desktop ?? [:], configuration: imageConfiguration,
                        provider: "com.apple.wallpaper.choice.image")
                }
                return (dictionary, 1)
            }
            var count = 0
            for (key, nested) in dictionary {
                let (updated, nestedCount) = updateNodes(
                    nested, imageConfiguration: imageConfiguration, saverConfiguration: saverConfiguration,
                    updateDesktopImages: updateDesktopImages)
                dictionary[key] = updated
                count += nestedCount
            }
            return (dictionary, count)
        }
        if let array = value as? [Any] {
            let results = array.map {
                updateNodes($0, imageConfiguration: imageConfiguration, saverConfiguration: saverConfiguration,
                            updateDesktopImages: updateDesktopImages)
            }
            return (results.map(\.0), results.reduce(0) { $0 + $1.1 })
        }
        return (value, 0)
    }

    private static func updatedNode(
        _ node: [String: Any], configuration: Data, provider: String
    ) -> [String: Any] {
        var node = node
        var content = node["Content"] as? [String: Any] ?? [:]
        // Files stays empty; current macOS resolves the image from Configuration.
        // NSWorkspace registers the native Settings selection after the agent reload.
        content["Choices"] = [["Configuration": configuration, "Files": [], "Provider": provider]]
        content["Shuffle"] = "$null"
        content.removeValue(forKey: "EncodedOptionValues")
        node["Content"] = content
        node["LastSet"] = Date()
        node["LastUse"] = Date()
        return node
    }

    private static func configurationData(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
}
