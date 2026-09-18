import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = AppStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store.bootstrap()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "MW"
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 540, height: 740)
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store)
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let button = statusItem?.button { showPopover(button) }
        return true
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showPopover(sender)
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "换下一张", action: #selector(applyRandomWallpaper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重新扫描图库", action: #selector(refreshLibrary), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MWall", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func applyRandomWallpaper() {
        store.applyRandomWallpaper()
    }

    @objc private func refreshLibrary() {
        store.refreshLibrary()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--snapshot-ui") {
    do {
        try UISnapshot.run()
        app.run()
    } catch {
        fputs("Snapshot failed: \(error)\n", stderr)
        exit(1)
    }
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
