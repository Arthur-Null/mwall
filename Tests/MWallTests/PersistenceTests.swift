import Foundation
import Testing

@testable import MWall

@Test func historySurvivesSaveAndLoad() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MWall-history-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let item = WallpaperItem(
        id: "fixture", url: URL(fileURLWithPath: "/tmp/fixture.jpg"), title: "Fixture",
        kind: .local, source: "Local")
    let entry = HistoryEntry(item: item, appliedAt: Date(timeIntervalSince1970: 1_781_112_034))
    Persistence.save([entry], to: url)
    #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("2026-06-10T17:20:34Z"))
    #expect(Persistence.load([HistoryEntry].self, from: url, fallback: []) == [entry])
}
