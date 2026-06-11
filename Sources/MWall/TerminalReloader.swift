import Foundation

enum TerminalReloader {
    static func reload(targets: Set<ThemeTarget>) -> [String] {
        var results: [String] = []

        if targets.contains(.kitty), commandExists("kitty") {
            let path = NSHomeDirectory() + "/.config/kitty/themes/mwall.conf"
            results.append(run("/usr/bin/env", ["kitty", "@", "set-colors", "-a", path], label: "Kitty"))
        }

        if targets.contains(.wezterm), commandExists("wezterm") {
            results.append(run("/usr/bin/env", ["wezterm", "cli", "reload-configuration"], label: "WezTerm"))
        }

        if targets.contains(.iterm2) {
            let path = StorePaths.appSupport.appendingPathComponent("MWall.itermcolors").path
            results.append(run("/usr/bin/open", [path], label: "iTerm2 import"))
        }

        if targets.contains(.terminal) {
            let path = StorePaths.appSupport.appendingPathComponent("Apply-MWall-Terminal.applescript").path
            results.append(run("/usr/bin/osascript", [path], label: "Terminal.app"))
        }

        return results
    }

    private static func commandExists(_ command: String) -> Bool {
        runRaw("/usr/bin/env", ["which", command]).exitCode == 0
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
