import Foundation
import Testing

@testable import MWall

@Test func updateComparesSemanticVersions() {
    #expect(UpdateService.isVersion("0.3.0", newerThan: "0.2.0"))
    #expect(UpdateService.isVersion("0.10.0", newerThan: "0.9.9"))
    #expect(UpdateService.isVersion("1.0.1", newerThan: "1.0"))
    #expect(!UpdateService.isVersion("0.2.0", newerThan: "0.2.0"))
    #expect(!UpdateService.isVersion("0.2", newerThan: "0.2.0"))
    #expect(!UpdateService.isVersion("0.1.9", newerThan: "0.2.0"))
}

@Test func updateSelectsArchiveForArchitecture() throws {
    let json = """
        {
          "tag_name": "v0.3.0",
          "body": "Notes",
          "html_url": "https://github.com/Arthur-Null/mwall/releases/tag/v0.3.0",
          "assets": [
            {"name": "MWall-v0.3.0-macos-arm64.zip", "browser_download_url": "https://example.com/arm.zip"},
            {"name": "MWall-v0.3.0-macos-arm64.zip.sha256", "browser_download_url": "https://example.com/arm.sha256"},
            {"name": "MWall-v0.3.0-macos-x86_64.zip", "browser_download_url": "https://example.com/intel.zip"}
          ]
        }
        """
    let release = try UpdateService.release(from: Data(json.utf8), architecture: "arm64")
    #expect(release.version == "0.3.0")
    #expect(release.notes == "Notes")
    #expect(release.archiveURL.absoluteString == "https://example.com/arm.zip")
    #expect(release.checksumURL.absoluteString == "https://example.com/arm.sha256")
    #expect(throws: UpdateError.missingAsset("MWall-v0.3.0-macos-x86_64.zip")) {
        try UpdateService.release(from: Data(json.utf8), architecture: "x86_64")
    }
}

@Test func updateReadsShasumOutputForArchive() {
    let digest = String(repeating: "a", count: 63) + "F"
    let text = "\(digest)  MWall-v0.3.0-macos-arm64.zip\n"
    #expect(
        UpdateService.expectedChecksum(in: text, archiveName: "MWall-v0.3.0-macos-arm64.zip")
            == digest.lowercased())
    #expect(
        UpdateService.expectedChecksum(in: "\(digest) *MWall.zip", archiveName: "MWall.zip")
            == digest.lowercased())
    #expect(UpdateService.expectedChecksum(in: text, archiveName: "other.zip") == nil)
    #expect(UpdateService.expectedChecksum(in: "abc  MWall.zip", archiveName: "MWall.zip") == nil)
}

@Test func updateSettingsDefaultWhenMissing() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.automaticallyChecksForUpdates)
    #expect(settings.lastUpdateCheck == 0)
    #expect(settings.skippedUpdateVersion.isEmpty)
}
