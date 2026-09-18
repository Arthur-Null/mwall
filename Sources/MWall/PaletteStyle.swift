import Foundation

enum PaletteStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case aether, faithful, soft, vivid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aether: "Aether"
        case .faithful: "忠实壁纸"
        case .soft: "柔和"
        case .vivid: "鲜艳"
        }
    }
    var detail: String {
        switch self {
        case .aether: "Aether 原版取色，保留其明暗与色彩取舍。"
        case .faithful: "保留壁纸的多组颜色，平衡原有彩度与文字可读性。"
        case .soft: "降低彩度，让壁纸的颜色更柔和。"
        case .vivid: "提高彩度，让壁纸的颜色更鲜明。"
        }
    }
}
