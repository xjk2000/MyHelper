import Foundation

enum PipelineStatus: String, Codable, Equatable, CaseIterable {
    case created
    case waitingForResource = "waiting_for_resource"
    case preparing
    case pending
    case running
    case success
    case failed
    case canceled
    case skipped
    case manual
    case scheduled
    case unknown

    var displayName: String {
        switch self {
        case .created: return "已创建"
        case .waitingForResource: return "等待资源"
        case .preparing: return "准备中"
        case .pending: return "等待中"
        case .running: return "运行中"
        case .success: return "成功"
        case .failed: return "失败"
        case .canceled: return "已取消"
        case .skipped: return "已跳过"
        case .manual: return "手动"
        case .scheduled: return "定时"
        case .unknown: return "未知"
        }
    }

    var symbol: String {
        switch self {
        case .created, .waitingForResource, .preparing, .pending: return "..."
        case .running: return "↻"
        case .success: return "✓"
        case .failed: return "✕"
        case .canceled: return "⊘"
        case .skipped: return "↷"
        case .manual: return "!"
        case .scheduled: return "◷"
        case .unknown: return "?"
        }
    }
}
