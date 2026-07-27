import Foundation

enum CloneItemState: Equatable, Sendable {
    case pending
    case running
    case succeeded
    case failed(String)
    case skipped
}

enum DirtyWorktreePolicy: String, CaseIterable, Identifiable, Sendable {
    case skip
    case stash
    case discard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skip: return "跳过该项目"
        case .stash: return "自动 stash 后继续"
        case .discard: return "丢弃所有改动后继续"
        }
    }

    var warningText: String {
        switch self {
        case .skip:
            return "存在未提交改动的项目会跳过。"
        case .stash:
            return "存在未提交改动的项目会先执行 git stash push -u。"
        case .discard:
            return "会执行 git reset --hard 和 git clean -fd，未提交改动不可恢复。"
        }
    }
}

struct CloneJob: Identifiable {
    let id: UUID = UUID()
    let projects: [GLProject]
    let mode: CloneMode
    let rootDirectory: URL
    let instance: GitLabInstance
    var checkoutBranches: [Int: String] = [:]
    var title: String = "同步进度"
    var cancelTitle: String = "取消同步"
    var progress: [Int: CloneItemState] = [:]
}
