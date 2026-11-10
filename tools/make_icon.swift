// Draws the MWall app icon and writes an .icns file.
// Usage: swift tools/make_icon.swift OUTPUT.icns [PREVIEW.png]
// A dusk wallpaper above the palette extracted from it: wallpaper in, theme out.
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
}

// Coordinates follow the 1024-point macOS icon grid with a top-left origin.
func drawIcon(_ c: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
    c.addPath(shape)
    c.setFillColor(color(0x15121F))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(shape)
    c.clip()

    let horizon: CGFloat = 724
    c.saveGState()
    c.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: horizon - body.minY))
    let sky = CGGradient(
        colorsSpace: space,
        colors: [color(0x2A3283), color(0x6A3C93), color(0xD2588A), color(0xF7A35C)] as CFArray,
        locations: [0, 0.38, 0.72, 1])!
    c.drawLinearGradient(
        sky, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: horizon), options: [])

    let sunCenter = CGPoint(x: 618, y: 500)
    let glow = CGGradient(
        colorsSpace: space, colors: [color(0xFFE2A0, 0.55), color(0xFFE2A0, 0)] as CFArray,
        locations: [0, 1])!
    c.drawRadialGradient(
        glow, startCenter: sunCenter, startRadius: 90, endCenter: sunCenter, endRadius: 260,
        options: [])
    c.setFillColor(color(0xFFE6A8))
    c.fillEllipse(in: CGRect(x: sunCenter.x - 104, y: sunCenter.y - 104, width: 208, height: 208))

    c.setFillColor(color(0x7B3F80))
    c.addPath(
        polygon([
            (100, 560), (232, 452), (346, 532), (486, 404), (640, 560), (770, 470),
            (924, 572), (924, horizon), (100, horizon),
        ]))
    c.fillPath()
    c.setFillColor(color(0x3B2659))
    c.addPath(
        polygon([
            (100, 652), (222, 572), (372, 660), (536, 566), (704, 668), (838, 608),
            (924, 650), (924, horizon), (100, horizon),
        ]))
    c.fillPath()
    c.restoreGState()

    // The extracted palette, sampled from the scene above.
    let swatches: [UInt32] = [0x2A3283, 0x6A3C93, 0xD2588A, 0xF7A35C, 0xFFE6A8]
    let inset: CGFloat = 72
    let gap: CGFloat = 26
    let width = (body.width - inset * 2 - gap * CGFloat(swatches.count - 1)) / CGFloat(swatches.count)
    let height: CGFloat = 92
    let top = horizon + (body.maxY - horizon - height) / 2
    for (index, hex) in swatches.enumerated() {
        let rect = CGRect(
            x: body.minX + inset + CGFloat(index) * (width + gap), y: top, width: width,
            height: height)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
        c.setFillColor(color(hex))
        c.fillPath()
    }
    c.restoreGState()

    c.addPath(shape)
    c.setStrokeColor(color(0xFFFFFF, 0.12))
    c.setLineWidth(3)
    c.strokePath()
}

func render(pixels: Int) -> Data {
    let c = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    c.translateBy(x: 0, y: CGFloat(pixels))
    c.scaleBy(x: scale, y: -scale)
    drawIcon(c)
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: make_icon.swift OUTPUT.icns [PREVIEW.png]\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("MWall-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2)
        .write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
if arguments.count >= 3 { try render(pixels: 1024).write(to: URL(fileURLWithPath: arguments[2])) }

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
