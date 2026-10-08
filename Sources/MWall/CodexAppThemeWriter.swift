import Darwin
import Foundation

/// Updates desktop colors through Codex's TOML writer, preserving other preferences.
enum CodexAppThemeWriter {
    static func write(
        _ palettes: TerminalPalettePair,
        directory: URL? = nil,
        executableURL: URL? = nil
    ) async throws -> [URL] {
        let root = directory ?? AgentThemeWriter.configDirectory(variable: "CODEX_HOME", fallback: ".codex")
        guard let executable = executableURL ?? codexExecutable() else {
            throw CodexAppSyncError.unavailable
        }
        let colors = try JSONSerialization.data(withJSONObject: [
            "appearanceDarkChromeTheme": themeColors(palettes.dark),
            "appearanceLightChromeTheme": themeColors(palettes.light)
        ])
        return try await Task.detached(priority: .utility) {
            try synchronize(colors: colors, directory: root, executableURL: executable)
        }.value
    }

    static func codexExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        let appRoots = [URL(fileURLWithPath: "/Applications"), homeDirectory.appendingPathComponent("Applications")]
        var candidates = appRoots.flatMap { root in
            ["ChatGPT.app", "Codex.app"].flatMap { app in
                ["codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex-cli/bin/codex", "codex"].map {
                    root.appendingPathComponent("\(app)/Contents/Resources/\($0)")
                }
            }
        }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map { URL(fileURLWithPath: $0) }
        candidates += [".local/bin/codex", ".cargo/bin/codex"].map { homeDirectory.appendingPathComponent($0) }
        candidates += (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func themeColors(_ palette: TerminalPalette) -> [String: Any] {
        [
            "accent": palette.accent.hex.lowercased(),
            "accentSource": "custom",
            "surface": palette.background.hex.lowercased(),
            "ink": palette.foreground.hex.lowercased(),
            "semanticColors": [
                "diffAdded": palette.normal[2].hex.lowercased(),
                "diffRemoved": palette.normal[1].hex.lowercased(),
                "skill": palette.normal[5].hex.lowercased()
            ]
        ]
    }

    private static func synchronize(colors: Data, directory: URL, executableURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // config/read omits the user layer when the file is absent. Create it exclusively
        // so first-time synchronization still obtains a version without overwriting a race.
        let file = directory.appendingPathComponent("config.toml")
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if descriptor >= 0 {
            Darwin.close(descriptor)
        } else if errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let client = try CodexConfigClient(executableURL: executableURL, directory: directory)
        defer { client.close() }
        _ = try client.request("initialize", params: [
            "clientInfo": ["name": "mwall", "version": "1.0.0"],
            "capabilities": ["experimentalApi": true]
        ])
        try client.notify("initialized")
        let read = try client.request("config/read", params: ["includeLayers": true])
        guard let layers = read["layers"] as? [[String: Any]],
              let layer = layers.first(where: {
                  guard let name = $0["name"] as? [String: Any], name["type"] as? String == "user",
                        let file = name["file"] as? String else { return false }
                  return URL(fileURLWithPath: file).resolvingSymlinksInPath()
                      == directory.appendingPathComponent("config.toml").resolvingSymlinksInPath()
              }), let version = layer["version"] as? String,
              let config = layer["config"] as? [String: Any],
              let themes = try JSONSerialization.jsonObject(with: colors) as? [String: [String: Any]] else {
            throw CodexAppSyncError.incompatible
        }
        let desktop = config["desktop"] as? [String: Any] ?? [:]
        let edits = configurationEdits(themes: themes, desktop: desktop)
        if !edits.isEmpty {
            _ = try client.request("config/batchWrite", params: [
                "edits": edits,
                "filePath": directory.appendingPathComponent("config.toml").path,
                "expectedVersion": version,
                "reloadUserConfig": false
            ])
        }
        return [directory.appendingPathComponent("config.toml")]
    }

    static func configurationEdits(themes: [String: [String: Any]], desktop: [String: Any]) -> [[String: Any]] {
        var edits: [[String: Any]] = []
        for key in themes.keys.sorted() {
            let existing = desktop[key] as? [String: Any] ?? [:]
            var desired = existing
            for (field, value) in themes[key] ?? [:] {
                if let colors = value as? [String: String] {
                    var semantic = existing[field] as? [String: Any] ?? [:]
                    colors.forEach { semantic[$0.key] = $0.value }
                    desired[field] = semantic
                } else {
                    desired[field] = value
                }
            }
            // The desktop schema requires these fields; an empty fonts table means system fonts.
            if desired["fonts"] == nil { desired["fonts"] = [String: String]() }
            if desired["contrast"] == nil { desired["contrast"] = 45 }
            if desired["opaqueWindows"] == nil { desired["opaqueWindows"] = false }
            if !NSDictionary(dictionary: existing).isEqual(to: desired) {
                edits.append(["keyPath": "desktop.\(key)", "mergeStrategy": "replace", "value": desired])
            }
        }
        return edits
    }
}

enum CodexAppSyncError: LocalizedError {
    case unavailable, incompatible, timeout, protocolFailure, rejected

    var errorDescription: String? {
        switch self {
        case .unavailable: "找不到 Codex CLI，请安装或更新 Codex App / CLI"
        case .incompatible: "Codex 配置接口不兼容，请更新 Codex App / CLI"
        case .timeout: "Codex 配置更新超时，请稍后重试"
        case .protocolFailure: "无法读取 Codex 配置接口响应，请更新 Codex App / CLI"
        case .rejected: "Codex 拒绝更新配置；请检查配置或重试，未覆盖其他编辑"
        }
    }
}

/// A short-lived app-server session; no shell, API key, model call, or user interaction.
final class CodexConfigClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var requestID = 0
    private let deadline: Date

    init(executableURL: URL, directory: URL, timeout: TimeInterval = 15) throws {
        deadline = Date().addingTimeInterval(timeout)
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = directory.path
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        // Never expose configuration contents or credentials in MWall's status text.
        process.standardError = FileHandle.nullDevice
        let descriptor = input.fileHandleForWriting.fileDescriptor
        guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) != -1,
              fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw CodexAppSyncError.protocolFailure
        }
        try process.run()
    }

    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        requestID += 1
        try send(["id": requestID, "method": method, "params": params])
        while true {
            let message = try readMessage()
            guard message["id"] as? Int == requestID else { continue }
            if message["error"] != nil { throw CodexAppSyncError.rejected }
            guard let result = message["result"] as? [String: Any] else { throw CodexAppSyncError.protocolFailure }
            return result
        }
    }

    func notify(_ method: String) throws { try send(["method": method]) }

    private func send(_ message: [String: Any]) throws {
        guard process.isRunning else { throw CodexAppSyncError.protocolFailure }
        let data = try JSONSerialization.data(withJSONObject: message) + Data([10])
        guard data.count <= 8 * 1024 * 1024 else { throw CodexAppSyncError.protocolFailure }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard Date() < deadline else { throw CodexAppSyncError.timeout }
                var descriptor = pollfd(fd: input.fileHandleForWriting.fileDescriptor, events: Int16(POLLOUT), revents: 0)
                let milliseconds = Int32(max(1, min(250, deadline.timeIntervalSinceNow * 1000)))
                let result = poll(&descriptor, 1, milliseconds)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw CodexAppSyncError.protocolFailure
                }
                if result == 0 { continue }
                let count = Darwin.write(descriptor.fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard count > 0 else { throw CodexAppSyncError.protocolFailure }
                offset += count
            }
        }
    }

    private func readMessage() throws -> [String: Any] {
        while true {
            guard Date() < deadline else { throw CodexAppSyncError.timeout }
            if let end = buffer.firstIndex(of: 10) {
                let line = buffer[..<end]
                let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                buffer.removeSubrange(...end)
                guard let message else { throw CodexAppSyncError.protocolFailure }
                return message
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(max(1, min(250, deadline.timeIntervalSinceNow * 1000)))
            let result = poll(&descriptor, 1, milliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                throw CodexAppSyncError.protocolFailure
            }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw CodexAppSyncError.protocolFailure }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 8 * 1024 * 1024 else { throw CodexAppSyncError.protocolFailure }
        }
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            // Bound cleanup even if a broken CLI ignores EOF or SIGTERM.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
}
