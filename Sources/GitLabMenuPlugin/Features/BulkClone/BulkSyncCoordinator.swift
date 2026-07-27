import Foundation

@MainActor
struct BulkSyncCoordinator {
    let settings: SettingsStore
    let projects: ProjectStore
    let jobs: CloneJobStore

    /// 触发指定项目集的同步。projectsToSync 为空则视为"该实例全部"。
    @discardableResult
    func sync(in instance: GitLabInstance,
              mode: CloneMode,
              projectsToSync: [GLProject] = [],
              rootDirectory: URL? = nil) async -> Bool {
        guard let token = settings.token(for: instance.id) else { return false }

        var chosen = projectsToSync
        if chosen.isEmpty {
            if projects.projects(for: instance.id).isEmpty {
                await projects.reload(instance: instance, token: token)
            }
            chosen = projects.projects(for: instance.id)
        }
        guard !chosen.isEmpty else { return false }
        let checkoutBranches = await resolveProductionBranches(
            for: chosen,
            in: instance,
            token: token
        )

        let job = CloneJob(
            projects: chosen,
            mode: mode,
            rootDirectory: rootDirectory ?? instance.defaultCloneRoot,
            instance: instance,
            checkoutBranches: checkoutBranches
        )
        jobs.reset(job: job)
        let cloneCfg = settings.config.clone
        let engine = CloneEngine(
            runner: GitRunner(),
            maxConcurrent: cloneCfg.maxConcurrency,
            token: token,
            stripTokenAfterClone: cloneCfg.stripTokenAfterClone
        )
        let task = Task.detached(priority: .userInitiated) { [jobs] in
            try? await engine.execute(
                job: job,
                progress: { id, state in
                    Task { @MainActor in jobs.update(projectId: id, state: state) }
                },
                output: { entry in
                    Task { @MainActor in jobs.appendLog(entry) }
                }
            )
            await MainActor.run { jobs.finish() }
        }
        jobs.setTask(task)
        return true
    }

    private func resolveProductionBranches(for projects: [GLProject],
                                           in instance: GitLabInstance,
                                           token: String) async -> [Int: String] {
        let client = GitLabClient(instance: instance, token: token)
        let resolver = ProductionBranchResolver(monitor: settings.config.monitor) { projectId, search in
            try await client.listBranches(projectId: projectId, search: search)
        }
        return await resolver.resolve(projects: projects)
    }
}

@MainActor
struct BulkBranchSwitchCoordinator {
    let settings: SettingsStore
    let jobs: CloneJobStore

    @discardableResult
    func switchBranches(in instance: GitLabInstance,
                        projectsToSwitch: [GLProject],
                        targetBranch: String,
                        baseBranches: [Int: String],
                        dirtyPolicy: DirtyWorktreePolicy,
                        rootDirectory: URL? = nil) async -> Bool {
        let target = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectsToSwitch.isEmpty, !target.isEmpty else { return false }
        let rootDirectory = rootDirectory ?? instance.defaultCloneRoot
        let token = settings.token(for: instance.id)
        var effectiveBaseBranches: [Int: String] = [:]
        if let token {
            let client = GitLabClient(instance: instance, token: token)
            let resolver = ProductionBranchResolver(monitor: settings.config.monitor) { projectId, search in
                try await client.listBranches(projectId: projectId, search: search)
            }
            effectiveBaseBranches = await resolver.resolve(projects: projectsToSwitch)
        }
        for (projectId, branch) in baseBranches {
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                effectiveBaseBranches[projectId] = trimmed
            }
        }

        let job = CloneJob(
            projects: projectsToSwitch,
            mode: .pull,
            rootDirectory: rootDirectory,
            instance: instance,
            title: "切分支进度",
            cancelTitle: "取消切分支"
        )
        jobs.reset(job: job)

        let engine = BranchSwitchEngine(
            runner: GitRunner(),
            maxConcurrent: settings.config.clone.maxConcurrency
        )
        let task = Task.detached(priority: .userInitiated) { [jobs] in
            await engine.execute(
                projects: projectsToSwitch,
                rootDirectory: rootDirectory,
                targetBranch: target,
                baseBranches: effectiveBaseBranches,
                dirtyPolicy: dirtyPolicy,
                progress: { id, state in
                    Task { @MainActor in jobs.update(projectId: id, state: state) }
                },
                output: { entry in
                    Task { @MainActor in jobs.appendLog(entry) }
                }
            )
            await MainActor.run { jobs.finish() }
        }
        jobs.setTask(task)
        return true
    }
}

struct ProductionBranchResolver {
    let monitor: MonitorSettings
    let branchProvider: (Int, String?) async throws -> [GLBranch]

    func resolve(projects: [GLProject]) async -> [Int: String] {
        await withTaskGroup(of: (Int, String)?.self) { group in
            for project in projects {
                guard let selector = monitor.productionWatch(for: project)?.selector else { continue }
                group.addTask {
                    do {
                        guard let branch = try await resolve(selector: selector, projectId: project.id) else {
                            return nil
                        }
                        return (project.id, branch)
                    } catch {
                        return nil
                    }
                }
            }

            var branches: [Int: String] = [:]
            for await pair in group {
                guard let (projectId, branch) = pair else { continue }
                branches[projectId] = branch
            }
            return branches
        }
    }

    private func resolve(selector: BranchSelector, projectId: Int) async throws -> String? {
        switch selector {
        case .fixed(let branch):
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .rule, .regex:
            return try await BranchResolver(branchProvider: branchProvider)
                .resolve(selector: selector, projectId: projectId)
        }
    }
}
