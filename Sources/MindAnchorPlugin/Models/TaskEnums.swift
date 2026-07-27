import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .todo: "待办"
        case .doing: "处理中"
        case .done: "已完成"
        }
    }
}

enum ParseState: String, Codable, CaseIterable {
    case pending
    case transcribing
    case parsing
    case parsed
    case failed

    var displayName: String {
        switch self {
        case .pending: "待处理"
        case .transcribing: "转写中"
        case .parsing: "解析中"
        case .parsed: "已解析"
        case .failed: "需整理"
        }
    }
}

enum SourceChannel: String, Codable, CaseIterable {
    case unknown
    case faceToFace
    case dingtalk
    case feishu

    var displayName: String {
        switch self {
        case .unknown: "#未知"
        case .faceToFace: "#面对面"
        case .dingtalk: "#钉钉"
        case .feishu: "#飞书"
        }
    }
}

enum TaskUrgency: String, Codable, CaseIterable {
    case normal
    case soon
    case overdue

    var displayName: String {
        switch self {
        case .normal: "正常"
        case .soon: "临近"
        case .overdue: "逾期"
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .soon: .yellow
        case .overdue: .red
        }
    }
}
