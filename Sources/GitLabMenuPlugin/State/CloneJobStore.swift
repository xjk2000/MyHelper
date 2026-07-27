import Foundation
import Observation

@Observable
@MainActor
final class CloneJobStore {
    var currentJob: CloneJob?
    /// projectId -> 状态
    var progress: [Int: CloneItemState] = [:]
    /// projectId -> stderr 摘要(失败时填)
    var errors: [Int: String] = [:]
    /// projectId -> git stdout/stderr 日志
    var logs: [Int: [GitOutput]] = [:]
    var isRunning: Bool = false
    var isCancelling: Bool = false

    @ObservationIgnored
    private var currentTask: Task<Void, Never>?

    func reset(job: CloneJob) {
        currentTask?.cancel()
        currentTask = nil
        currentJob = job
        progress = Dictionary(uniqueKeysWithValues:
            job.projects.map { ($0.id, .pending) })
        errors = [:]
        logs = [:]
        isRunning = true
        isCancelling = false
    }

    func setTask(_ task: Task<Void, Never>) {
        currentTask = task
    }

    func update(projectId: Int, state: CloneItemState) {
        progress[projectId] = state
        if case .failed(let msg) = state { errors[projectId] = msg }
    }

    func appendLog(_ entry: GitOutput) {
        guard let projectId = entry.projectId else { return }
        var entries = logs[projectId, default: []]
        entries.append(entry)
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        logs[projectId] = entries
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        currentTask?.cancel()
        for (projectId, state) in progress {
            switch state {
            case .pending, .running:
                update(projectId: projectId, state: .failed("已取消"))
                appendLog(GitOutput(
                    projectId: projectId,
                    stream: .stderr,
                    message: "已请求取消同步"
                ))
            default:
                break
            }
        }
    }

    func finish() {
        currentTask = nil
        isRunning = false
        isCancelling = false
    }

    var summary: (success: Int, failed: Int, skipped: Int) {
        var s = 0, f = 0, k = 0
        for v in progress.values {
            switch v {
            case .succeeded: s += 1
            case .failed:    f += 1
            case .skipped:   k += 1
            default: break
            }
        }
        return (s, f, k)
    }
}
