import AppKit
import CoreGraphics
import Foundation

enum WallpaperService {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "webp"]

    /// Installs a durable copy under Application Support, then applies it to the desktop.
    /// Returns the stable file URL actually used by the desktop / wallpaper store.
    @discardableResult
    static func setDesktopImage(_ url: URL, allScreens: Bool) throws -> URL {
        let appliedURL = try installAppliedWallpaper(url)
        if allScreens {
            try setScreenImages(appliedURL, screens: NSScreen.screens)
            try setEveryDesktopImage(appliedURL)
            restartWallpaperAgent()
            return appliedURL
        }

        try setScreenImages(appliedURL, screens: [NSScreen.main].compactMap { $0 })
        return appliedURL
    }

    /// Copies `sourceURL` into `directory` (default: `StorePaths.applied`) so Unsplash cache
    /// cleanup cannot delete the live desktop image, and System Settings can keep a resolvable
    /// Files reference.
    static func installAppliedWallpaper(
        _ sourceURL: URL,
        into directory: URL = StorePaths.applied
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("current.\(ext)")
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

        let temporaryURL = directory
            .appendingPathComponent(".current-\(UUID().uuidString).\(ext)")
        try fm.copyItem(at: sourceURL, to: temporaryURL)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fm.moveItem(at: temporaryURL, to: destination)
        }

        let keepName = destination.lastPathComponent
        if let leftovers = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in leftovers where url.lastPathComponent != keepName {
                try? fm.removeItem(at: url)
            }
        }

        return destination
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

    private static func setEveryDesktopImage(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: WallpaperStore.systemIndexURL.path) {
            _ = try WallpaperStore.updateSystemIndex(imageURL: url)
            return
        }

        let script = """
        tell application "System Events"
            repeat with currentDesktop in desktops
                set picture of currentDesktop to \(appleScriptString(url.path))
            end repeat
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            throw NSError(
                domain: "MWall.Wallpaper",
                code: 124,
                userInfo: [NSLocalizedDescriptionKey: "设置所有桌面壁纸超时，请确认已允许 MWall 控制 System Events。"]
            )
        }

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "MWall.Wallpaper",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output?.isEmpty == false
                        ? output!
                        : "无法设置所有桌面壁纸，请确认已允许 MWall 控制 System Events。"
                ]
            )
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

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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
