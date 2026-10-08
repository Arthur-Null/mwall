import Foundation

enum TerminalReloader {
    static func reload(targets: Set<ThemeTarget>) -> [String] {
        var results: [String] = []

        if targets.contains(.kitty) {
            results.append(reloadKitty())
        }

        return results
    }

    /// Applies `~/.config/kitty/themes/mwall.conf` to running Kitty instances.
    /// Resolves the GUI `.app` binary and listen sockets explicitly — Launch Services
    /// PATH often has no `kitty`, so `which kitty` alone fails from MWall.app.
    static func reloadKitty(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        guard let kitty = kittyExecutable(fileManager: fileManager) else {
            return "Kitty: skipped"
        }

        let theme = homeDirectory + "/.config/kitty/themes/mwall.conf"
        guard fileManager.fileExists(atPath: theme) else {
            return "Kitty: skipped"
        }

        let sockets = kittyListenSockets(fileManager: fileManager, homeDirectory: homeDirectory)
        if sockets.isEmpty {
            // Fall back to Kitty's own discovery (KITTY_LISTEN_ON / defaults).
            return run(
                kitty.path,
                ["@", "set-colors", "-a", "--configured", theme],
                label: "Kitty"
            )
        }

        var ok = 0
        for socket in sockets {
            let result = runRaw(
                kitty.path,
                ["@", "--to", "unix:\(socket.path)", "set-colors", "-a", "--configured", theme]
            )
            if result.exitCode == 0 {
                ok += 1
            }
        }
        return ok > 0 ? "Kitty: ok" : "Kitty: skipped"
    }

    static func kittyExecutable(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory(),
        pathCandidates: [String]? = nil
    ) -> URL? {
        let candidates = pathCandidates ?? [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "\(homeDirectory)/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let which = runRaw("/usr/bin/env", ["which", "kitty"])
        let path = which.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if which.exitCode == 0, !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Kitty may create `kitty-$USER.sock` or `kitty-$USER.sock-<pid>` under `/tmp`.
    static func kittyListenSockets(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> [URL] {
        let user = URL(fileURLWithPath: homeDirectory).lastPathComponent
        // Kitty's listen_on uses /tmp, not NSTemporaryDirectory()'s per-user T folder.
        let tmp = URL(fileURLWithPath: "/tmp")
        let prefix = "kitty-\(user).sock"
        let contents = (try? fileManager.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { url in
                let last = url.lastPathComponent
                return last == prefix || last.hasPrefix(prefix + "-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func run(_ executable: String, _ arguments: [String], label: String) -> String {
        let result = runRaw(executable, arguments)
        return result.exitCode == 0 ? "\(label): ok" : "\(label): skipped"
    }

    private static func runRaw(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (127, error.localizedDescription)
        }
    }
}
