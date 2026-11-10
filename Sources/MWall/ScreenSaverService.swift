import CoreFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenSaverService {
    static let moduleURL = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions/iLifeSlideshows.appex", isDirectory: false)

    static var imageDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MWall Screen Saver", isDirectory: true)
    }

    /// Photos reads a dedicated folder with one PNG, so even wallpaper formats that
    /// Photos cannot enumerate directly can be used without rotating through old images.
    @discardableResult
    static func prepareImage(_ imageURL: URL, into directory: URL = imageDirectory) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else {
            throw failure("无法读取用于屏保的壁纸图片")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw failure("无法创建屏保图片")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw failure("无法编码屏保图片") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("wallpaper.png")
        try (data as Data).write(to: url, options: .atomic)
        return url
    }

    static func configurePhotoSource(
        folder: URL = imageDirectory,
        persist: (String, [String: Any]) throws -> Void = writePreferences
    ) throws {
        // Do not touch com.apple.screensaver: activation time, clock and password
        // preferences are independent of the image selected by MWall.
        try persist("com.apple.ScreenSaverPhotoChooser", [
            "SelectedSource": 4,
            "SelectedFolderPath": folder.path,
            "CustomFolderDict": ["identifier": folder.path, "name": "MWall"],
            "ShufflesPhotos": false
        ])
        try persist("com.apple.ScreenSaver.iLifeSlideShows", ["styleKey": "Classic"])
    }

    static func removeOldImages(keeping folder: URL) {
        let root = folder.deletingLastPathComponent()
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for child in children where child.lastPathComponent.hasPrefix("current-") && child.lastPathComponent != folder.lastPathComponent {
            try? FileManager.default.removeItem(at: child)
        }
    }

    private static func writePreferences(domain: String, values: [String: Any]) throws {
        CFPreferencesSetMultiple(
            values as CFDictionary, nil, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw failure("无法保存照片屏保设置")
        }
        if domain == "com.apple.ScreenSaverPhotoChooser" {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("kPhotoChooserSourceChangedNotification"), object: nil,
                userInfo: nil, deliverImmediately: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MWall.ScreenSaver", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
