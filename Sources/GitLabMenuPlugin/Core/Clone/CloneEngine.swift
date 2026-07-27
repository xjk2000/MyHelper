import Foundation

actor CloneEngine {
    private let runner: GitRunning
    private let maxConcurrent: Int
    private let token: String
    private let stripTokenAfterClone: Bool

    init(runner: GitRunning, maxConcurrent: Int,
         token: String, stripTokenAfterClone: Bool) {
        self.runner = runner
        self.maxConcurrent = max(1, maxConcurrent)
        self.token = token
        self.stripTokenAfterClone = stripTokenAfterClone
    }

    /// 执行整个 Job。progress 回调在 actor 内串行触发(顺序按完成顺序)。
    func execute(job: CloneJob,
                 progress: @escaping CloneProgressCallback,
                 output: CloneLogCallback? = nil) async throws {
        try FileManager.default.createDirectory(
            at: job.rootDirectory, withIntermediateDirectories: true
        )

        let sem = AsyncSemaphore(value: maxConcurrent)
        await withTaskGroup(of: Void.self) { group in
            for project in job.projects {
                group.addTask { [self] in
                    await sem.wait()
                    if Task.isCancelled {
                        await sem.signal()
                        return
                    }
                    progress(project.id, .running)
                    let state = await self.processOne(project: project, job: job, output: output)
                    progress(project.id, state)
                    await sem.signal()
                }
            }
        }
    }

    // MARK: - Per project

    private func processOne(project: GLProject,
                            job: CloneJob,
                            output: CloneLogCallback?) async -> CloneItemState {
        let target = job.rootDirectory
            .appendingPathComponent(project.pathWithNamespace)
        let gitDir = target.appendingPathComponent(".git")
        let exists = FileManager.default.fileExists(atPath: gitDir.path)

        do {
            let state: CloneItemState
            let clonedProtocol: CloneProtocol?
            switch (job.mode, exists) {
            case (.skip, true):
                state = .skipped
                clonedProtocol = nil
            case (.skip, false), (.pull, false), (.reclone, false):
                state = try await doClone(project: project, target: target,
                                           protocolKind: job.instance.cloneProtocol,
                                           output: output)
                clonedProtocol = job.instance.cloneProtocol
            case (.pull, true):
                state = try await doPull(project: project, target: target, output: output)
                clonedProtocol = nil
            case (.reclone, true):
                try FileManager.default.removeItem(at: target)
                state = try await doClone(project: project, target: target,
                                           protocolKind: job.instance.cloneProtocol,
                                           output: output)
                clonedProtocol = job.instance.cloneProtocol
            }
            let finalState = try await checkoutConfiguredBranchIfNeeded(
                state: state,
                project: project,
                target: target,
                branch: job.checkoutBranches[project.id],
                output: output
            )
            if let clonedProtocol {
                await stripCredentialsAfterCloneIfNeeded(
                    project: project,
                    target: target,
                    protocolKind: clonedProtocol
                )
            }
            return finalState
        } catch is CancellationError {
            return .failed("已取消")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func doClone(project: GLProject, target: URL,
                         protocolKind: CloneProtocol,
                         output: CloneLogCallback?) async throws -> CloneItemState {
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )
        let urlString = CloneURLBuilder.cloneURL(
            for: project, protocolKind: protocolKind, token: token
        )
        let result = try await runner.run(
            ["clone", "--progress", urlString, target.path],
            cwd: nil,
            output: projectOutput(project.id, output)
        )
        guard result.succeeded else {
            return .failed(sanitize(result.stderr))
        }
        return .succeeded
    }

    private func stripCredentialsAfterCloneIfNeeded(project: GLProject,
                                                    target: URL,
                                                    protocolKind: CloneProtocol) async {
        guard protocolKind == .https, stripTokenAfterClone else { return }
        let urlString = CloneURLBuilder.cloneURL(
            for: project,
            protocolKind: protocolKind,
            token: token
        )
        let stripped = CloneURLBuilder.stripCredentials(urlString)
        _ = try? await runner.run(
            ["remote", "set-url", "origin", stripped], cwd: target
        )
    }

    private func doPull(project: GLProject,
                        target: URL,
                        output: CloneLogCallback?) async throws -> CloneItemState {
        let fetch = try await runner.run(
            ["fetch", "--all", "--prune", "--progress"],
            cwd: target,
            output: projectOutput(project.id, output)
        )
        if !fetch.succeeded { return .failed(sanitize(fetch.stderr)) }
        let pull = try await runner.run(
            ["pull", "--ff-only", "--progress"],
            cwd: target,
            output: projectOutput(project.id, output)
        )
        return pull.succeeded ? .succeeded : .failed(sanitize(pull.stderr))
    }

    private func checkoutConfiguredBranchIfNeeded(state: CloneItemState,
                                                  project: GLProject,
                                                  target: URL,
                                                  branch: String?,
                                                  output: CloneLogCallback?) async throws -> CloneItemState {
        guard case .succeeded = state else { return state }
        guard let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else { return state }

        let sourceRef = "origin/\(branch)"
        let fetch = try await runner.run(
            ["fetch", "origin", "--prune", "--progress", "refs/heads/\(branch):refs/remotes/\(sourceRef)"],
            cwd: target,
            output: projectOutput(project.id, output)
        )
        guard fetch.succeeded else {
            return .failed("找不到远程生产分支 \(sourceRef): \(cleanGitError(fetch.stderr))")
        }

        if try await localBranchExists(branch, repo: target, projectId: project.id, output: output) {
            let switched = try await runner.run(
                ["switch", branch],
                cwd: target,
                output: projectOutput(project.id, output)
            )
            guard switched.succeeded else { return .failed(cleanGitError(switched.stderr)) }

            let upstream = try await runner.run(
                ["branch", "--set-upstream-to=\(sourceRef)", branch],
                cwd: target,
                output: projectOutput(project.id, output)
            )
            guard upstream.succeeded else { return .failed(cleanGitError(upstream.stderr)) }

            let pull = try await runner.run(
                ["pull", "--ff-only", "--progress"],
                cwd: target,
                output: projectOutput(project.id, output)
            )
            return pull.succeeded ? .succeeded : .failed(cleanGitError(pull.stderr))
        }

        let created = try await runner.run(
            ["checkout", "-b", branch, sourceRef],
            cwd: target,
            output: projectOutput(project.id, output)
        )
        guard created.succeeded else { return .failed(cleanGitError(created.stderr)) }

        let upstream = try await runner.run(
            ["branch", "--set-upstream-to=\(sourceRef)", branch],
            cwd: target,
            output: projectOutput(project.id, output)
        )
        return upstream.succeeded ? .succeeded : .failed(cleanGitError(upstream.stderr))
    }

    /// 移除任何形式的 https://user:pass@... 凭证后再展示
    private func sanitize(_ s: String) -> String {
        let pattern = #"https://[^/\s]+:[^@\s]+@"#
        return s.replacingOccurrences(of: pattern, with: "https://***@",
                                       options: .regularExpression)
    }

    private func projectOutput(_ projectId: Int,
                               _ output: CloneLogCallback?) -> GitOutputCallback? {
        guard let output else { return nil }
        return { [token] entry in
            output(GitOutput(
                projectId: projectId,
                stream: entry.stream,
                message: Self.sanitizeMessage(entry.message, token: token)
            ))
        }
    }

    private static func sanitizeMessage(_ message: String, token: String) -> String {
        var sanitized = message.replacingOccurrences(
            of: #"https://[^/\s]+:[^@\s]+@"#,
            with: "https://***@",
            options: .regularExpression
        )
        if !token.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: token, with: "***")
        }
        return sanitized
    }

    private func localBranchExists(_ branch: String,
                                   repo: URL,
                                   projectId: Int,
                                   output: CloneLogCallback?) async throws -> Bool {
        let result = try await runner.run(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            cwd: repo,
            output: projectOutput(projectId, output)
        )
        return result.succeeded
    }

    private func cleanGitError(_ value: String) -> String {
        let sanitized = sanitize(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Git 命令执行失败" : sanitized
    }
}

actor BranchSwitchEngine {
    private let runner: GitRunning
    private let maxConcurrent: Int

    init(runner: GitRunning, maxConcurrent: Int) {
        self.runner = runner
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func execute(projects: [GLProject],
                 rootDirectory: URL,
                 targetBranch: String,
                 baseBranches: [Int: String],
                 dirtyPolicy: DirtyWorktreePolicy,
                 progress: @escaping CloneProgressCallback,
                 output: CloneLogCallback? = nil) async {
        let sem = AsyncSemaphore(value: maxConcurrent)
        await withTaskGroup(of: Void.self) { group in
            for project in projects {
                group.addTask { [self] in
                    await sem.wait()
                    if Task.isCancelled {
                        await sem.signal()
                        return
                    }
                    progress(project.id, .running)
                    let baseBranch = baseBranches[project.id] ?? project.defaultBranch ?? "main"
                    let state = await self.processOne(
                        project: project,
                        rootDirectory: rootDirectory,
                        targetBranch: targetBranch,
                        baseBranch: baseBranch,
                        dirtyPolicy: dirtyPolicy,
                        output: output
                    )
                    progress(project.id, state)
                    await sem.signal()
                }
            }
        }
    }

    private func processOne(project: GLProject,
                            rootDirectory: URL,
                            targetBranch: String,
                            baseBranch: String,
                            dirtyPolicy: DirtyWorktreePolicy,
                            output: CloneLogCallback?) async -> CloneItemState {
        let repo = rootDirectory.appendingPathComponent(project.pathWithNamespace)
        let gitDir = repo.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            emit("本地仓库不存在，请先同步/克隆", projectId: project.id, stream: .stderr, output: output)
            return .skipped
        }

        let target = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return .failed("目标分支不能为空") }
        guard !base.isEmpty else { return .failed("基准分支不能为空") }

        do {
            if try await hasDirtyWorktree(repo: repo, projectId: project.id, output: output) {
                switch dirtyPolicy {
                case .skip:
                    emit("存在未提交改动，已按策略跳过", projectId: project.id, stream: .stderr, output: output)
                    return .skipped
                case .stash:
                    let message = "GitLabMenu before switch to \(target) \(Self.timestamp())"
                    let stash = try await runner.run(
                        ["stash", "push", "-u", "-m", message],
                        cwd: repo,
                        output: projectOutput(project.id, output)
                    )
                    guard stash.succeeded else { return .failed(clean(stash.stderr)) }
                case .discard:
                    let reset = try await runner.run(
                        ["reset", "--hard"],
                        cwd: repo,
                        output: projectOutput(project.id, output)
                    )
                    guard reset.succeeded else { return .failed(clean(reset.stderr)) }
                    let cleanResult = try await runner.run(
                        ["clean", "-fd"],
                        cwd: repo,
                        output: projectOutput(project.id, output)
                    )
                    guard cleanResult.succeeded else { return .failed(clean(cleanResult.stderr)) }
                }
            }

            if try await localBranchExists(target, repo: repo, projectId: project.id, output: output) {
                let switched = try await runner.run(
                    ["switch", target],
                    cwd: repo,
                    output: projectOutput(project.id, output)
                )
                return switched.succeeded ? .succeeded : .failed(clean(switched.stderr))
            }

            let fetch = try await runner.run(
                ["fetch", "origin", "--prune", "--progress", "refs/heads/\(base):refs/remotes/origin/\(base)"],
                cwd: repo,
                output: projectOutput(project.id, output)
            )
            guard fetch.succeeded else {
                return .failed("找不到远程基准分支 origin/\(base): \(clean(fetch.stderr))")
            }

            let sourceRef = "origin/\(base)"
            let created = try await runner.run(
                ["checkout", "-b", target, sourceRef],
                cwd: repo,
                output: projectOutput(project.id, output)
            )
            guard created.succeeded else { return .failed(clean(created.stderr)) }

            let upstream = try await runner.run(
                ["branch", "--set-upstream-to=\(sourceRef)", target],
                cwd: repo,
                output: projectOutput(project.id, output)
            )
            return upstream.succeeded ? .succeeded : .failed(clean(upstream.stderr))
        } catch is CancellationError {
            return .failed("已取消")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func hasDirtyWorktree(repo: URL,
                                  projectId: Int,
                                  output: CloneLogCallback?) async throws -> Bool {
        let result = try await runner.run(
            ["status", "--porcelain"],
            cwd: repo,
            output: projectOutput(projectId, output)
        )
        guard result.succeeded else { throw BranchSwitchError.git(clean(result.stderr)) }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func localBranchExists(_ branch: String,
                                   repo: URL,
                                   projectId: Int,
                                   output: CloneLogCallback?) async throws -> Bool {
        let result = try await runner.run(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            cwd: repo,
            output: projectOutput(projectId, output)
        )
        return result.succeeded
    }

    private func projectOutput(_ projectId: Int,
                               _ output: CloneLogCallback?) -> GitOutputCallback? {
        guard let output else { return nil }
        return { entry in
            output(GitOutput(
                projectId: projectId,
                stream: entry.stream,
                message: entry.message
            ))
        }
    }

    private func emit(_ message: String,
                      projectId: Int,
                      stream: GitOutputStream,
                      output: CloneLogCallback?) {
        output?(GitOutput(projectId: projectId, stream: stream, message: message))
    }

    private func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Git 命令执行失败" : trimmed
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

private enum BranchSwitchError: LocalizedError {
    case git(String)

    var errorDescription: String? {
        switch self {
        case .git(let message): return message
        }
    }
}

/// 简单的 async 信号量
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.permits = value }

    func wait() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let w = waiters.first {
            waiters.removeFirst()
            w.resume()
        } else {
            permits += 1
        }
    }
}
