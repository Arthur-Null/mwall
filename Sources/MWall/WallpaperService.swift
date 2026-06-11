import AppKit
import CoreGraphics
import Foundation

enum WallpaperService {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "webp"]

    static func setDesktopImage(_ url: URL, allScreens: Bool) throws {
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
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
