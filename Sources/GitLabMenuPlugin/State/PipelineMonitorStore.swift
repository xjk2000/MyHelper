import Foundation
import Observation

struct PipelineMonitorStatus: Equatable {
    let target: MonitorTarget
    let watch: MonitorBranchWatch
    var resolvedBranch: String?
    var status: PipelineStatus
    var webURL: URL?
    var updatedAt: Date?
    var startedAt: Date?
    var baselineDuration: TimeInterval?
    var errorMessage: String?
    var isLoading: Bool
}

struct PipelineMonitorRequest: Equatable {
    let target: MonitorTarget
    let watch: MonitorBranchWatch
    let branch: String
}

private struct PipelineMonitorWorkItem {
    let statusId: String
    let target: MonitorTarget
    let watch: MonitorBranchWatch
    let instance: GitLabInstance
    let token: String
}

@Observable
final class PipelineMonitorStore {
    typealias Fetcher = (GitLabInstance, String, PipelineMonitorRequest) async throws -> PipelineResult
    typealias BranchProvider = (GitLabInstance, String, MonitorTarget, String?) async throws -> [GLBranch]
    typealias DurationProvider = (GitLabInstance, String, MonitorTarget, String) async throws -> [TimeInterval]

    private let fetcher: Fetcher
    private let branchProvider: BranchProvider
    private let durationProvider: DurationProvider
    var statuses: [String: PipelineMonitorStatus] = [:]
    var isRefreshing = false

    init(fetcher: @escaping Fetcher = { instance, token, target in
        let client = GitLabClient(instance: instance, token: token)
        // 普通监控已在 fetch 前解析出实际分支，菜单栏只需查询该分支最新 Pipeline。
        if target.watch.ciSelector == nil {
            return try await client.latestPipeline(
                projectId: target.target.projectId,
                branch: target.branch
            )
        }
        if case .fixed = target.watch.pipelineSelector {
            return try await client.latestPipeline(
                projectId: target.target.projectId,
                branch: target.branch
            )
        }
        return try await client.currentOrLatestPipeline(
            projectId: target.target.projectId,
            selector: target.watch.pipelineSelector
        )
    }, branchProvider: @escaping BranchProvider = { instance, token, target, search in
        let client = GitLabClient(instance: instance, token: token)
        return try await client.listBranches(projectId: target.projectId, search: search)
    }, durationProvider: @escaping DurationProvider = { instance, token, target, branch in
        let client = GitLabClient(instance: instance, token: token)
        return try await client.recentSuccessDurations(projectId: target.projectId, branch: branch)
    }) {
        self.fetcher = fetcher
        self.branchProvider = branchProvider
        self.durationProvider = durationProvider
    }

    @MainActor
    func refreshAll(config: AppConfig, tokenProvider: (UUID) -> String?) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let instances = Dictionary(uniqueKeysWithValues: config.instances.map { ($0.id, $0) })
        let activeIds = Set(config.monitor.targets.flatMap { target in
            target.watches
                .filter(\.monitorEnabled)
                .map { target.statusId(for: $0) }
        })
        statuses = statuses.filter { activeIds.contains($0.key) }

        var workItems: [PipelineMonitorWorkItem] = []

        for target in config.monitor.targets {
            for watch in target.watches {
                guard watch.monitorEnabled else { continue }
                let statusId = target.statusId(for: watch)
                statuses[statusId] = PipelineMonitorStatus(
                    target: target,
                    watch: watch,
                    resolvedBranch: statuses[statusId]?.resolvedBranch,
                    status: statuses[statusId]?.status ?? .unknown,
                    webURL: statuses[statusId]?.webURL,
                    updatedAt: statuses[statusId]?.updatedAt,
                    startedAt: statuses[statusId]?.startedAt,
                    baselineDuration: statuses[statusId]?.baselineDuration,
                    errorMessage: nil,
                    isLoading: true
                )

                guard let instance = instances[target.instanceId] else {
                    statuses[statusId] = PipelineMonitorStatus(
                        target: target,
                        watch: watch,
                        resolvedBranch: nil,
                        status: .unknown,
                        webURL: nil,
                        updatedAt: nil,
                        startedAt: nil,
                        baselineDuration: nil,
                        errorMessage: "缺少 GitLab 实例",
                        isLoading: false
                    )
                    continue
                }

                guard let token = tokenProvider(target.instanceId), !token.isEmpty else {
                    statuses[statusId] = PipelineMonitorStatus(
                        target: target,
                        watch: watch,
                        resolvedBranch: nil,
                        status: .unknown,
                        webURL: nil,
                        updatedAt: nil,
                        startedAt: nil,
                        baselineDuration: nil,
                        errorMessage: "缺少 PAT",
                        isLoading: false
                    )
                    continue
                }

                workItems.append(PipelineMonitorWorkItem(
                    statusId: statusId,
                    target: target,
                    watch: watch,
                    instance: instance,
                    token: token
                ))
            }
        }

        await withTaskGroup(of: (String, PipelineMonitorStatus).self) { group in
            for item in workItems {
                group.addTask {
                    let status = await self.refreshStatus(item)
                    return (item.statusId, status)
                }
            }

            for await (statusId, status) in group {
                statuses[statusId] = status
            }
        }
    }

    private func refreshStatus(_ item: PipelineMonitorWorkItem) async -> PipelineMonitorStatus {
        do {
            let branch: String
            if shouldResolveBranchBeforeFetch(item.watch) {
                let resolver = BranchResolver { _, search in
                    try await self.branchProvider(item.instance, item.token, item.target, search)
                }
                guard let resolvedBranch = try await resolver.resolve(
                    selector: item.watch.pipelineSelector,
                    projectId: item.target.projectId
                ) else {
                    return PipelineMonitorStatus(
                        target: item.target,
                        watch: item.watch,
                        resolvedBranch: nil,
                        status: .unknown,
                        webURL: nil,
                        updatedAt: nil,
                        startedAt: nil,
                        baselineDuration: nil,
                        errorMessage: "未匹配到分支",
                        isLoading: false
                    )
                }
                branch = resolvedBranch
            } else {
                branch = item.watch.pipelineSelector.displayHint
            }

            let result = try await fetcher(
                item.instance,
                item.token,
                PipelineMonitorRequest(target: item.target, watch: item.watch, branch: branch)
            )
            let pipelineBranch = result.ref ?? branch
            var baseline: TimeInterval?
            if result.status == .running || result.status == .pending {
                let durations = (try? await durationProvider(
                    item.instance,
                    item.token,
                    item.target,
                    pipelineBranch
                )) ?? []
                if !durations.isEmpty {
                    baseline = durations.reduce(0, +) / TimeInterval(durations.count)
                }
            }
            return PipelineMonitorStatus(
                target: item.target,
                watch: item.watch,
                resolvedBranch: pipelineBranch,
                status: result.status,
                webURL: result.webURL,
                updatedAt: result.updatedAt,
                startedAt: result.startedAt,
                baselineDuration: baseline,
                errorMessage: nil,
                isLoading: false
            )
        } catch {
            return PipelineMonitorStatus(
                target: item.target,
                watch: item.watch,
                resolvedBranch: nil,
                status: .unknown,
                webURL: nil,
                updatedAt: nil,
                startedAt: nil,
                baselineDuration: nil,
                errorMessage: error.localizedDescription,
                isLoading: false
            )
        }
    }

    private func shouldResolveBranchBeforeFetch(_ watch: MonitorBranchWatch) -> Bool {
        if watch.ciSelector != nil {
            return false
        }
        return true
    }
}
