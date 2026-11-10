import CoreGraphics
import ImageIO
import Foundation
import Testing
@testable import MWall

@Test func linkedWallpaperIndexIsRecognized() throws {
    try withScreenSaverIndex([
        "AllSpacesAndDisplays": ["Type": "linked", "Linked": wallpaperNode("old")],
        "SystemDefault": ["Type": "linked", "Linked": wallpaperNode("old")],
        "Displays": [:], "Spaces": [:]
    ]) { url in
        let count = try WallpaperStore.updateIndex(
            at: url, imageURL: URL(fileURLWithPath: "/tmp/new wallpaper.jpg"))
        #expect(count == 2)
        let root = try readScreenSaverIndex(url)
        let scope = try #require(root["AllSpacesAndDisplays"] as? [String: Any])
        let node = try #require(scope["Linked"] as? [String: Any])
        #expect(try imagePath(node) == "file:///tmp/new%20wallpaper.jpg")
    }
}

private func wallpaperNode(_ marker: String) -> [String: Any] {
    ["Content": ["Choices": [["Provider": "old-provider", "Configuration": Data(),
                             "Files": [], "Marker": marker]], "Shuffle": "$null"],
     "LastSet": Date(timeIntervalSince1970: 0)]
}

private func withScreenSaverIndex(_ root: [String: Any], body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Index.plist")
    try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
    try body(url)
}

private func readScreenSaverIndex(_ url: URL) throws -> [String: Any] {
    try #require(PropertyListSerialization.propertyList(
        from: Data(contentsOf: url), options: [], format: nil) as? [String: Any])
}

private func imagePath(_ node: [String: Any]) throws -> String {
    let content = try #require(node["Content"] as? [String: Any])
    let choices = try #require(content["Choices"] as? [[String: Any]])
    let data = try #require(choices.first?["Configuration"] as? Data)
    let config = try #require(PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any])
    return try #require((config["url"] as? [String: Any])?["relative"] as? String)
}

@Test func linkedIndexBecomesExplicitDesktopAndPhotoScreenSaver() throws {
    let linked = wallpaperNode("original")
    try withScreenSaverIndex([
        "AllSpacesAndDisplays": ["Type": "linked", "Linked": linked, "Unrelated": "keep"],
        "Displays": ["external": ["Type": "individual", "Desktop": linked, "Idle": linked]],
        "Spaces": ["hidden": ["Default": ["Desktop": linked]]],
        "SystemDefault": ["Type": "linked", "Linked": linked],
        "UnrelatedRoot": 42
    ]) { url in
        let count = try WallpaperStore.updateIndex(
            at: url, imageURL: URL(fileURLWithPath: "/tmp/new.jpg"),
            screenSaverModuleURL: ScreenSaverService.moduleURL)
        #expect(count == 4)
        let root = try readScreenSaverIndex(url)
        #expect(root["UnrelatedRoot"] as? Int == 42)
        let scopes = collectScopes(root)
        #expect(scopes.count == 4)
        for scope in scopes {
            #expect(scope["Type"] as? String == "individual")
            #expect(scope["Linked"] == nil)
            #expect(try imagePath(#require(scope["Desktop"] as? [String: Any])) == "file:///tmp/new.jpg")
            let idle = try #require(scope["Idle"] as? [String: Any])
            let content = try #require(idle["Content"] as? [String: Any])
            let choices = try #require(content["Choices"] as? [[String: Any]])
            #expect(choices.count == 1)
            #expect(choices[0]["Provider"] as? String == "com.apple.wallpaper.choice.screen-saver")
            let data = try #require(choices[0]["Configuration"] as? Data)
            let config = try #require(PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any])
            #expect((config["module"] as? [String: Any])?["relative"] as? String
                    == ScreenSaverService.moduleURL.absoluteString)
        }
        #expect((root["AllSpacesAndDisplays"] as? [String: Any])?["Unrelated"] as? String == "keep")
    }
}

@Test func screenSaverOnlyUpdatePreservesEveryDesktop() throws {
    let original = wallpaperNode("keep-this-desktop")
    try withScreenSaverIndex([
        "AllSpacesAndDisplays": ["Type": "linked", "Linked": original],
        "Spaces": ["hidden": ["Desktop": original, "Idle": wallpaperNode("old-saver")]]
    ]) { url in
        _ = try WallpaperStore.updateIndex(
            at: url, imageURL: URL(fileURLWithPath: "/tmp/new.jpg"),
            screenSaverModuleURL: ScreenSaverService.moduleURL, updateDesktopImages: false)
        let scopes = collectScopes(try readScreenSaverIndex(url))
        #expect(scopes.count == 2)
        for scope in scopes {
            let desktop = try #require(scope["Desktop"] as? [String: Any])
            #expect(NSDictionary(dictionary: desktop).isEqual(to: original))
            #expect(scope["Idle"] != nil)
        }
    }
}

@Test func unknownWallpaperIndexIsNotOverwritten() throws {
    try withScreenSaverIndex(["FutureLayout": ["Other": "keep"]]) { url in
        let before = try Data(contentsOf: url)
        #expect(throws: NSError.self) {
            try WallpaperStore.updateIndex(
                at: url, imageURL: URL(fileURLWithPath: "/tmp/new.jpg"),
                screenSaverModuleURL: ScreenSaverService.moduleURL)
        }
        #expect(try Data(contentsOf: url) == before)
    }
}

@Test func photoScreenSaverPreferencesDoNotChangeActivationOrSecurity() throws {
    var written: [String: [String: Any]] = [:]
    let folder = URL(fileURLWithPath: "/tmp/MWall screen saver")
    try ScreenSaverService.configurePhotoSource(folder: folder) { domain, values in
        written[domain] = values
    }
    #expect(Set(written.keys) == ["com.apple.ScreenSaverPhotoChooser", "com.apple.ScreenSaver.iLifeSlideShows"])
    let chooser = try #require(written["com.apple.ScreenSaverPhotoChooser"])
    #expect(chooser["SelectedSource"] as? Int == 4)
    #expect(chooser["SelectedFolderPath"] as? String == folder.path)
    #expect(chooser["ShufflesPhotos"] as? Bool == false)
    #expect(written["com.apple.ScreenSaver.iLifeSlideShows"]?["styleKey"] as? String == "Classic")
}

@Test func screenSaverImageReplacesOnlyItsOwnPNG() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.png")
    func writeColor(red: UInt8, blue: UInt8) throws {
        let pixels = Data(Array(repeating: [red, 0, blue, 255], count: 32).flatMap { $0 })
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(
            width: 8, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(
            source as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
    try writeColor(red: 255, blue: 0)
    let output = folder.appendingPathComponent("ScreenSaver")
    let first = try ScreenSaverService.prepareImage(source, into: output)
    let before = try Data(contentsOf: first)
    try writeColor(red: 0, blue: 255)
    let second = try ScreenSaverService.prepareImage(source, into: output)
    #expect(first == second)
    #expect(try Data(contentsOf: second) != before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["wallpaper.png"])
    let decoded = try #require(CGImageSourceCreateWithURL(second as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
    #expect(image.width == 8)
    #expect(image.height == 4)
    let context = try #require(CGContext(
        data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 32,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 4))
    let rgba = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    #expect(rgba[0] < 10 && rgba[2] > 240 && rgba[3] == 255)
}

private func collectScopes(_ value: Any) -> [[String: Any]] {
    if let dictionary = value as? [String: Any] {
        if dictionary["Desktop"] != nil || dictionary["Linked"] != nil { return [dictionary] }
        return dictionary.values.flatMap(collectScopes)
    }
    return (value as? [Any] ?? []).flatMap(collectScopes)
}


@Test func photoScreenSaverModuleMatchesNativeURLExactly() {
    #expect(ScreenSaverService.moduleURL.absoluteString ==
            "file:///System/Library/ExtensionKit/Extensions/iLifeSlideshows.appex")
}

@Test func preparingWallpaperKeepsTheCurrentlyReferencedImage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.jpg")
    try Data([1, 2, 3]).write(to: source)
    let applied = folder.appendingPathComponent("Applied")
    let old = try WallpaperService.installAppliedWallpaper(source, into: applied)
    _ = try WallpaperService.installAppliedWallpaper(source, into: applied)
    // Preparation can be followed by a failed index write or a single-screen apply.
    #expect(FileManager.default.fileExists(atPath: old.path))
}


@Test func screenSaverCleanupKeepsCurrentDirectoryAndUnrelatedFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let current = root.appendingPathComponent("current-new", isDirectory: true)
    let old = root.appendingPathComponent("current-old", isDirectory: true)
    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = current.appendingPathComponent("wallpaper.png")
    try Data([1]).write(to: image)
    let unrelated = root.appendingPathComponent("user-note.txt")
    try Data([2]).write(to: unrelated)
    ScreenSaverService.removeOldImages(keeping: current)
    #expect(FileManager.default.fileExists(atPath: image.path))
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}
