import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AetherPalette {
    static let revision = "f0ae849966cc038a21808170b21e07772cb3619c"

    static func generate(from url: URL, executable: URL? = nil) throws -> TerminalPalettePair {
        let binary = try executable ?? locateExecutable()
        let image = try compatibleImage(url)
        defer { if image != url { try? FileManager.default.removeItem(at: image) } }
        return try TerminalPalettePair(
            dark: extract(image, light: false, executable: binary),
            light: extract(image, light: true, executable: binary)
        )
    }

    // Upstream decodes JPEG, PNG, GIF and WebP. Import macOS-native formats as
    // sRGB PNG without changing Aether's sampling, extraction or color roles.
    private static func compatibleImage(_ url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source) as String?
        else { throw failure("无法读取这张壁纸。") }
        let passthrough = [
            UTType.jpeg.identifier, UTType.png.identifier, UTType.gif.identifier, "org.webmproject.webp",
        ]
        if passthrough.contains(type) { return url }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw failure("无法解码这张壁纸。") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { throw failure("无法转换这张壁纸。") }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwall-aether-\(UUID().uuidString).png")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: temporary) } }
        guard
            let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw failure("无法创建临时壁纸。") }
        CGImageDestinationAddImage(destination, converted, nil)
        guard CGImageDestinationFinalize(destination) else { throw failure("无法转换这张壁纸。") }
        complete = true
        return temporary
    }

    private static func locateExecutable() throws -> URL {
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["MWALL_AETHER_BIN"].map { URL(fileURLWithPath: $0) },
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mwall-aether"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/mwall-aether"),
        ].compactMap { $0 }
        guard let result = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else {
            throw failure("Aether 引擎未安装。开发运行请先执行 tools/build_aether.sh。")
        }
        return result
    }

    private struct Result: Decodable {
        let colors: [String]
        let mode: String
        let lightMode: Bool
    }

    private static func extract(_ image: URL, light: Bool, executable: URL) throws -> TerminalPalette {
        let process = Process()
        process.executableURL = executable
        process.arguments =
            ["--extract-palette", image.path, "--extract-mode", "normal", "--json"]
            + (light ? ["--light-mode"] : [])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            struct ExtractionError: Decodable { let error: String }
            let detail = (try? JSONDecoder().decode(ExtractionError.self, from: data))?.error
            throw failure(detail.map { "Aether 取色失败：\($0)" } ?? "Aether 取色失败，请换一张图片重试。")
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        guard result.colors.count == 16, result.mode == "normal", result.lightMode == light else {
            throw failure("Aether 返回了不完整的配色。")
        }
        let colors = try result.colors.map { value -> RGBColor in
            guard value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
                let rgb = UInt32(value.dropFirst(), radix: 16)
            else {
                throw failure("Aether 返回了无效颜色。")
            }
            return RGBColor(r: Int(rgb >> 16), g: Int((rgb >> 8) & 255), b: Int(rgb & 255))
        }
        // Exactly upstream CLI MapColorsToRoles; no MWall recoloring.
        return TerminalPalette(
            source: colors[4], background: colors[0], foreground: colors[7],
            cursor: colors[7], cursorText: colors[0],
            selectionBackground: colors[7], selectionForeground: colors[0],
            normal: Array(colors.prefix(8)), bright: Array(colors.suffix(8)), accentOverride: colors[4]
        )
    }

    private static func failure(_ description: String) -> NSError {
        NSError(domain: "MWall.Aether", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
