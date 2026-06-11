import Foundation
import ServiceManagement

enum LoginItemService {
    static var canRegister: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard canRegister else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard canRegister else {
            throw NSError(
                domain: "MWall.LoginItem",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "启动项注册需要先打包并运行 MWall.app，swift run 模式不支持"]
            )
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
