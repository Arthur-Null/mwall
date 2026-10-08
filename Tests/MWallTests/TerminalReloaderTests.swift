import Foundation
@testable import MWall
import Testing

@Test func kittyExecutablePrefersConfiguredCandidates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWall-kitty-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let missing = root.appendingPathComponent("missing/kitty")
    let present = root.appendingPathComponent("Applications/kitty.app/Contents/MacOS/kitty")
    try FileManager.default.createDirectory(
        at: present.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: present)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: present.path)

    let resolved = TerminalReloader.kittyExecutable(
        pathCandidates: [missing.path, present.path]
    )
    #expect(resolved?.path == present.path)
}

@Test func reloadKittySkipsWhenThemeFileMissing() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWall-kitty-home-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(TerminalReloader.reloadKitty(homeDirectory: root.path) == "Kitty: skipped")
}

@Test func kittyListenSocketsOnlyMatchUserPrefix() {
    let user = URL(fileURLWithPath: NSHomeDirectory()).lastPathComponent
    let prefix = "kitty-\(user).sock"
    for socket in TerminalReloader.kittyListenSockets() {
        let name = socket.lastPathComponent
        #expect(name == prefix || name.hasPrefix(prefix + "-"))
    }
}

@Test func kittyExecutableFindsApplicationsBundleOnThisMac() {
    let app = "/Applications/kitty.app/Contents/MacOS/kitty"
    guard FileManager.default.isExecutableFile(atPath: app) else { return }
    #expect(TerminalReloader.kittyExecutable()?.path == app)
}
