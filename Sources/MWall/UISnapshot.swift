// Render the real SwiftUI surface with isolated fixture state for visual QA.
// Usage: mwall --snapshot-ui OUTPUT CACHE WIDTH HEIGHT PAGE APPEARANCE STYLE
import AppKit
import SwiftUI

@MainActor
enum UISnapshot {
    static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 9, let width = Double(args[4]), let height = Double(args[5]),
            width >= 440, height >= 620,
            let page = MWallPage.allCases.first(where: { $0.id == args[6] }),
            let style = PaletteStyle(rawValue: args[8])
        else {
            throw NSError(
                domain: "MWall.Snapshot", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Usage: mwall --snapshot-ui OUTPUT CACHE WIDTH HEIGHT 壁纸|配色|设置 light|dark aether|faithful|soft|vivid"
                ])
        }
        let output = URL(fileURLWithPath: args[2])
        let cache = URL(fileURLWithPath: args[3])
        let originals = try FileManager.default.contentsOfDirectory(
            at: cache.appendingPathComponent("Full"), includingPropertiesForKeys: nil
        )
        .filter { ["jpg", "png", "jpeg"].contains($0.pathExtension.lowercased()) }.sorted {
            $0.path < $1.path
        }
        let metadata = try JSONDecoder().decode(
            [WallpaperItem].self, from: Data(contentsOf: cache.appendingPathComponent("metadata.json")))
        let items = originals.map { url -> WallpaperItem in
            let id =
                "unsplash:"
                + url.deletingPathExtension().lastPathComponent.replacingOccurrences(
                    of: "unsplash-", with: "")
            let saved = metadata.first { $0.id == id }
            return WallpaperItem(
                id: id, url: url, title: saved?.title, kind: .unsplash,
                source: saved?.source, fullLocalURL: url)
        }
        let store = AppStore(previewItems: items)
        store.settings.paletteStyle = style
        if let selected = items.first(where: { $0.id.contains("aaIN3y2zcMQ") }) {
            store.selectWallpaper(selected)
        }
        let dark = args[7] == "dark"
        NSApp.setActivationPolicy(.prohibited)
        let root = ContentView(initialPage: page).environmentObject(store)
            .preferredColorScheme(dark ? .dark : .light)
            .frame(width: width, height: height)
        let view = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        window.orderBack(nil)
        Task { @MainActor in
            await store.refreshPalettePreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                do {
                    view.layoutSubtreeIfNeeded()
                    view.display()
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        throw NSError(domain: "MWall.Snapshot", code: 2)
                    }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    guard let png = rep.representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "MWall.Snapshot", code: 3)
                    }
                    try FileManager.default.createDirectory(
                        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: output)
                    print("SNAPSHOT \(output.path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                    window.orderOut(nil)
                    exit(0)
                } catch {
                    fputs("Snapshot failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
    }
}
