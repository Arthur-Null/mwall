import Foundation
@testable import MWall
import Testing

@Test func updateIndexRewritesEveryDesktopNode() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWallTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let indexURL = temporaryDirectory.appendingPathComponent("Index.plist")
    let imageURL = URL(fileURLWithPath: "/Users/test/Pictures/new wallpaper.jpg")
    let oldConfiguration = try configurationData(for: URL(fileURLWithPath: "/Users/test/Pictures/old.jpg"))
    let plist = fixtureIndex(configuration: oldConfiguration)
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    try data.write(to: indexURL)

    let count = try WallpaperStore.updateIndex(at: indexURL, imageURL: imageURL)

    #expect(count == 3)
    let updatedData = try Data(contentsOf: indexURL)
    let updatedPlist = try PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil)
    let configurations = collectDesktopConfigurations(from: updatedPlist)
    #expect(configurations.count == 3)
    for configuration in configurations {
        #expect(configuration["type"] as? String == "imageFile")
        let url = configuration["url"] as? [String: Any]
        #expect(url?["relative"] as? String == imageURL.absoluteString)
        #expect(configuration["relative"] == nil)
    }

    let filesEntries = collectDesktopFiles(from: updatedPlist)
    #expect(filesEntries.count == 3)
    for files in filesEntries {
        #expect(files.count == 1)
        #expect(files[0]["relative"] as? String == imageURL.absoluteString)
    }
}

@Test func installAppliedWallpaperCopiesIntoStableDirectory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWallApplied-\(UUID().uuidString)", isDirectory: true)
    let applied = root.appendingPathComponent("Applied", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("unsplash-cache.jpg")
    try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: source)

    let installed = try WallpaperService.installAppliedWallpaper(source, into: applied)
    #expect(installed.lastPathComponent == "current.jpg")
    #expect(installed.deletingLastPathComponent().path == applied.path)
    #expect(FileManager.default.fileExists(atPath: installed.path))
    #expect(try Data(contentsOf: installed) == Data([0xFF, 0xD8, 0xFF, 0xD9]))

    let pngSource = root.appendingPathComponent("other.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngSource)
    let installedPNG = try WallpaperService.installAppliedWallpaper(pngSource, into: applied)
    #expect(installedPNG.lastPathComponent == "current.png")
    #expect(!FileManager.default.fileExists(atPath: installed.path))
    #expect(try Data(contentsOf: installedPNG) == Data([0x89, 0x50, 0x4E, 0x47]))
}

private func fixtureIndex(configuration: Data) -> NSDictionary {
    let desktop: NSMutableDictionary = [
        "Content": [
            "Choices": [
                [
                    "Configuration": configuration,
                    "Files": [],
                    "Provider": "com.apple.wallpaper.choice.image"
                ]
            ],
            "Shuffle": "$null"
        ],
        "LastSet": Date(timeIntervalSince1970: 0),
        "LastUse": Date(timeIntervalSince1970: 0)
    ]

    return [
        "Displays": [
            "display-a": [
                "Desktop": desktop.mutableCopy()
            ]
        ],
        "Spaces": [
            "space-a": [
                "Default": [
                    "Desktop": desktop.mutableCopy()
                ],
                "Displays": [
                    "display-a": [
                        "Desktop": desktop.mutableCopy()
                    ]
                ]
            ]
        ]
    ]
}

private func configurationData(for imageURL: URL) throws -> Data {
    try PropertyListSerialization.data(
        fromPropertyList: [
            "type": "imageFile",
            "url": [
                "relative": imageURL.absoluteString
            ]
        ],
        format: .binary,
        options: 0
    )
}

private func collectDesktopConfigurations(from value: Any) -> [[String: Any]] {
    var configurations: [[String: Any]] = []
    if let dictionary = value as? [String: Any] {
        if let desktop = dictionary["Desktop"] as? [String: Any],
           let content = desktop["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let configurationData = firstChoice["Configuration"] as? Data,
           let configuration = try? PropertyListSerialization.propertyList(from: configurationData, options: [], format: nil) as? [String: Any] {
            configurations.append(configuration)
        }
        for nestedValue in dictionary.values {
            configurations.append(contentsOf: collectDesktopConfigurations(from: nestedValue))
        }
    } else if let array = value as? [Any] {
        for nestedValue in array {
            configurations.append(contentsOf: collectDesktopConfigurations(from: nestedValue))
        }
    }
    return configurations
}

private func collectDesktopFiles(from value: Any) -> [[[String: Any]]] {
    var results: [[[String: Any]]] = []
    if let dictionary = value as? [String: Any] {
        if let desktop = dictionary["Desktop"] as? [String: Any],
           let content = desktop["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let files = firstChoice["Files"] as? [[String: Any]] {
            results.append(files)
        }
        for nestedValue in dictionary.values {
            results.append(contentsOf: collectDesktopFiles(from: nestedValue))
        }
    } else if let array = value as? [Any] {
        for nestedValue in array {
            results.append(contentsOf: collectDesktopFiles(from: nestedValue))
        }
    }
    return results
}
