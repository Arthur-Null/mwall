import AppKit
import CoreGraphics
import Foundation

enum WallpaperService {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "webp"]

    /// Installs a durable copy under Application Support, then applies it to the desktop.
    /// Returns the stable file URL actually used by the desktop / wallpaper store.
    @discardableResult
    static func setDesktopImage(_ url: URL, allScreens: Bool) throws -> URL {
        guard FileManager.default.fileExists(atPath: WallpaperStore.systemIndexURL.path),
              FileManager.default.fileExists(atPath: ScreenSaverService.moduleURL.path) else {
            throw NSError(domain: "MWall.Wallpaper", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无法找到系统壁纸索引或照片屏保组件"
            ])
        }
        let appliedURL = try installAppliedWallpaper(url)
        let screenSaverFolder = ScreenSaverService.imageDirectory
            .appendingPathComponent("current-\(UUID().uuidString)", isDirectory: true)
        try ScreenSaverService.prepareImage(appliedURL, into: screenSaverFolder)
        try applyInstalledWallpaper(
            setScreens: {
                try setScreenImages(
                    appliedURL, screens: allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 })
            },
            updateStore: {
                _ = try WallpaperStore.updateSystemIndex(
                    imageURL: appliedURL, screenSaverModuleURL: ScreenSaverService.moduleURL,
                    updateDesktopImages: allScreens)
            },
            configureScreenSaver: { try ScreenSaverService.configurePhotoSource(folder: screenSaverFolder) },
            restartAgent: restartWallpaperAgent
        )
        ScreenSaverService.removeOldImages(keeping: screenSaverFolder)
        if allScreens {
            cleanupAppliedWallpapers(keeping: appliedURL)
        }
        return appliedURL
    }

    static func applyInstalledWallpaper(
        setScreens: () throws -> Void,
        updateStore: () throws -> Void,
        configureScreenSaver: () throws -> Void,
        restartAgent: () -> Void
    ) throws {
        try updateStore()
        try configureScreenSaver()
        restartAgent()
        // Register with NSWorkspace after reloading the store, so Settings keeps
        // the native image selection. Other Spaces retain their desktop in single-screen mode.
        try setScreens()
    }
    /// Copies `sourceURL` into `directory` (default: `StorePaths.applied`) so Unsplash cache
    /// cleanup cannot delete the live desktop image or its native Settings reference.
    ///
    /// Each apply uses a unique `current-<uuid>.<ext>` name. Replacing the same `current.jpg`
    /// path in place leaves `NSWorkspace` / WallpaperAgent on an unchanged URL, so the desktop
    /// does not refresh even though file bytes changed.
    static func installAppliedWallpaper(
        _ sourceURL: URL,
        into directory: URL = StorePaths.applied
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("current-\(UUID().uuidString).\(ext)")
        if sourceURL.standardizedFileURL == destination.standardizedFileURL {
            return destination
        }

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw NSError(
                domain: "MWall.Wallpaper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "找不到壁纸文件：\(sourceURL.path)"]
            )
        }

        try fm.copyItem(at: sourceURL, to: destination)

        return destination
    }

    // Only after a successful all-desktop apply can older images be unreferenced.
    // Single-screen applications and failures must preserve the other desktop images.
    static func cleanupAppliedWallpapers(keeping destination: URL) {
        let directory = destination.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return }
        for file in files where file.lastPathComponent != destination.lastPathComponent && file.lastPathComponent.hasPrefix("current-") {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
    private static func setScreenImages(_ url: URL, screens: [NSScreen]) throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    private static func restartWallpaperAgent() {
        guard FileManager.default.fileExists(atPath: WallpaperStore.systemIndexURL.path) else {
            return
        }

        for processName in ["WallpaperAgent", "WallpaperImageExtension"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [processName]
            try? process.run()
            process.waitUntilExit()
        }
    }

    static func imageFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                urls.append(url)
            }
        }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func ensureBuiltInWallpapers() {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(at: StorePaths.builtIns, includingPropertiesForKeys: nil)).map({ $0.isEmpty }) ?? true else {
            return
        }

        let specs: [(String, [NSColor])] = [
            ("aurora", [.systemTeal, .systemPurple, .systemIndigo, .black]),
            ("ember", [.systemOrange, .systemPink, .systemRed, .black]),
            ("moss", [.systemGreen, .systemTeal, .systemBrown, .black]),
            ("dawn", [.systemYellow, .systemPink, .systemBlue, .white])
        ]

        for spec in specs {
            let url = StorePaths.builtIns.appendingPathComponent("\(spec.0).png")
            generateGradientWallpaper(colors: spec.1, destination: url)
        }
    }

    private static func generateGradientWallpaper(colors: [NSColor], destination: URL) {
        let width = 3840
        let height = 2160
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        let cgColors = colors.map { ($0.usingColorSpace(.sRGB) ?? $0).cgColor } as CFArray
        let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cgColors, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        context.setBlendMode(.screen)
        for i in 0..<16 {
            let alpha = CGFloat(0.06 + Double(i % 4) * 0.025)
            let color = colors[i % colors.count].withAlphaComponent(alpha).cgColor
            context.setFillColor(color)
            let x = CGFloat((i * 577) % width)
            let y = CGFloat((i * 331) % height)
            let size = CGFloat(520 + (i % 5) * 180)
            context.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        }

        guard let image = context.makeImage(),
              let destinationRef = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)
        else {
            return
        }
        CGImageDestinationAddImage(destinationRef, image, nil)
        CGImageDestinationFinalize(destinationRef)
    }
}
