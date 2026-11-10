import Foundation
import Testing
@testable import MWall

@Test func wallpaperRegistersNativePreviewAfterStoreReload() throws {
    var operations: [String] = []
    var registeredPreview: String?
    try WallpaperService.applyInstalledWallpaper(
        setScreens: { operations.append("native"); registeredPreview = "new-image" },
        updateStore: { operations.append("store") },
        configureScreenSaver: { operations.append("photos") },
        restartAgent: { operations.append("reload"); registeredPreview = nil }
    )
    #expect(operations == ["store", "photos", "reload", "native"])
    #expect(registeredPreview == "new-image")
}

@Test func wallpaperFailedStoreWriteDoesNotConfigureScreenSaverOrRestartAgent() {
    var operations: [String] = []
    #expect(throws: CocoaError.self) {
        try WallpaperService.applyInstalledWallpaper(
            setScreens: { operations.append("native") },
            updateStore: { throw CocoaError(.fileWriteNoPermission) },
            configureScreenSaver: { operations.append("photos") },
            restartAgent: { operations.append("reload") }
        )
    }
    #expect(operations.isEmpty)
}

@Test func wallpaperScreenSaverFailureIsReportedBeforeReload() {
    var reloaded = false
    var nativeApplied = false
    #expect(throws: CocoaError.self) {
        try WallpaperService.applyInstalledWallpaper(
            setScreens: { nativeApplied = true }, updateStore: {},
            configureScreenSaver: { throw CocoaError(.fileWriteNoPermission) },
            restartAgent: { reloaded = true }
        )
    }
    #expect(!reloaded)
    #expect(!nativeApplied)
}
