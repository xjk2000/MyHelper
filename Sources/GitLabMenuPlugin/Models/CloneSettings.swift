import Foundation

enum CloneMode: String, Codable, CaseIterable, Identifiable {
    case skip, pull, reclone
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .skip:    return "跳过已存在"
        case .pull:    return "拉取更新"
        case .reclone: return "强制重新克隆"
        }
    }
}

struct CloneSettings: Codable, Equatable {
    var defaultMode: CloneMode = .pull
    var maxConcurrency: Int = 6
    var stripTokenAfterClone: Bool = true
}
