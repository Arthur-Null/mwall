import CryptoKit
import Foundation

struct AppRelease: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let archiveURL: URL
    let checksumURL: URL
}

enum UpdateError: LocalizedError, Equatable {
    case notBundled
    case missingAsset(String)
    case checksumMismatch
    case invalidBundle
    case notWritable(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBundled:
            "自动更新需要运行打包后的 MWall.app，swift run 模式不支持"
        case .missingAsset(let name):
            "最新版本缺少当前机型的安装包 \(name)"
        case .checksumMismatch:
            "安装包校验值不匹配，已取消更新"
        case .invalidBundle:
            "下载的安装包不是有效的 MWall.app"
        case .notWritable(let path):
            "没有写入 \(path) 的权限，请手动下载更新"
        case .commandFailed(let message):
            message
        }
    }
}

/// Checks GitHub Releases for a newer build and swaps it in place of the running bundle.
/// Release archives follow `tools/archive_app.sh`: `MWall-v<version>-macos-<arch>.zip`
/// plus a `.sha256` file produced by `shasum -a 256`.
enum UpdateService {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/Arthur-Null/mwall/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var canInstall: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var architecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    static func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MWall/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let data = try await download(request)
        return try release(from: data, architecture: architecture)
    }

    static func release(from data: Data, architecture: String) throws -> AppRelease {
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst()) : payload.tagName
        let archiveName = "MWall-v\(version)-macos-\(architecture).zip"
        let assets = Dictionary(
            payload.assets.map { ($0.name, $0.browserDownloadURL) }, uniquingKeysWith: { a, _ in a })
        guard let archive = assets[archiveName], let checksum = assets[archiveName + ".sha256"]
        else {
            throw UpdateError.missingAsset(archiveName)
        }
        return AppRelease(
            version: version, notes: payload.body ?? "", pageURL: payload.htmlURL,
            archiveURL: archive, checksumURL: checksum)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Reads the digest from `shasum -a 256` output for the named archive.
    static func expectedChecksum(in text: String, archiveName: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, fields[1].trimmingPrefix("*") == archiveName else { continue }
            let digest = fields[0].lowercased()
            if digest.count == 64, digest.allSatisfy(\.isHexDigit) { return digest }
        }
        return nil
    }

    /// Downloads, verifies and installs the release over the running bundle.
    /// Returns the installed app URL for relaunching.
    static func install(_ release: AppRelease, over appURL: URL = Bundle.main.bundleURL)
        async throws -> URL
    {
        guard appURL.pathExtension == "app" else { throw UpdateError.notBundled }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        let fm = FileManager.default
        let workDirectory = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL,
            create: true)
        defer { try? fm.removeItem(at: workDirectory) }

        let archiveName = release.archiveURL.lastPathComponent
        let archive = workDirectory.appendingPathComponent(archiveName)
        try await download(URLRequest(url: release.archiveURL)).write(to: archive)
        let checksumText = String(
            decoding: try await download(URLRequest(url: release.checksumURL)), as: UTF8.self)
        guard let expected = expectedChecksum(in: checksumText, archiveName: archiveName),
            try sha256(of: archive) == expected
        else {
            throw UpdateError.checksumMismatch
        }

        let extracted = workDirectory.appendingPathComponent("Extracted", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let newApp = extracted.appendingPathComponent("MWall.app", isDirectory: true)
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle(url: appURL)?.bundleIdentifier,
            info?["CFBundleShortVersionString"] as? String == release.version
        else {
            throw UpdateError.invalidBundle
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

        return try fm.replaceItemAt(appURL, withItemAt: newApp) ?? appURL
    }

    /// Opens the app again once the current process has exited.
    static func relaunch(_ appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh", "\(ProcessInfo.processInfo.processIdentifier)", appURL.path,
        ]
        try process.run()
    }

    private static func download(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.commandFailed("检查更新失败：HTTP \(http.statusCode)")
        }
        return data
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed("\(executable) 失败：\(detail)")
        }
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case assets
    }
}
