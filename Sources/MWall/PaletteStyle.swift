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
        case .soft: "贴近 Noctalia muted：浅色背景接近低饱和中性底，强调色也更克制。"
        case .vivid: "提高彩度，让壁纸的颜色更鲜明。"
        case .faithful: "保留壁纸色相，浅色背景只留淡淡色调，避免大面积高饱和底。"
        case .aether: "Aether 原版取色，保留其明暗与色彩取舍。"
        }
    }
}
