import SwiftUI

struct ProjectListWindow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProjectStore.self) private var store
    @Environment(CloneJobStore.self) private var jobs
    @State private var vm = ProjectListViewModel()
    @State private var currentInstanceId: UUID?
    @State private var showProgress: Bool = false
    @State private var pendingReclone: Bool = false
    @State private var pendingBranchSwitch: Bool = false
    @State private var pendingDiscardBranchSwitch: Bool = false
    @State private var pendingMonitorProject: GLProject?
    @State private var monitorWatchesDraft: [MonitorBranchWatch] = []
    @State private var branchSwitchTarget: String = ""
    @State private var branchSwitchBaseDrafts: [Int: String] = [:]
    @State private var branchSwitchDirtyPolicy: DirtyWorktreePolicy = .skip
    @State private var selectedCloneRoot: URL?
    @State private var monitorMessage: String?
    @State private var resolvedMonitorBranches: [String: MonitorBranchResolution] = [:]

    var currentInstance: GitLabInstance? {
        guard let id = currentInstanceId
                ?? settings.currentInstanceId
                ?? settings.config.instances.first?.id
        else { return nil }
        return settings.config.instances.first(where: { $0.id == id })
    }

    var projects: [GLProject] {
        guard let id = currentInstance?.id else { return [] }
        return store.projects(for: id)
    }

    private var selectedProjects: [GLProject] {
        projects.filter { vm.selectedIds.contains($0.id) }
    }

    private var activeCloneRoot: URL? {
        selectedCloneRoot ?? currentInstance?.defaultCloneRoot
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            list
                .overlay {
                    if settings.config.instances.isEmpty {
                        ContentUnavailableView(
                            MainDashboardCopy.configureGitLabTitle,
                            systemImage: "server.rack",
                            description: Text(MainDashboardCopy.emptyProjectHint)
                        )
                    } else if let inst = currentInstance,
                              let error = store.lastError[inst.id],
                              !error.isEmpty {
                        ContentUnavailableView(
                            "项目列表加载失败",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else if let inst = currentInstance,
                              store.loading[inst.id] != true,
                              projects.isEmpty {
                        ContentUnavailableView(
                            "还没有项目列表",
                            systemImage: "tray.and.arrow.down",
                            description: Text("点击“刷新列表”从当前 GitLab 实例拉取项目。")
                        )
                    }
                }
                .glassPanel(cornerRadius: 16, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            footer
        }
        .padding(12)
        .frame(minWidth: 720, minHeight: 480)
        .frostedWindowBackground()
        .onAppear { reloadIfNeeded() }
        .onChange(of: currentInstanceId) { _, _ in
            selectedCloneRoot = nil
            reloadIfNeeded()
        }
        .task(id: monitorResolutionTaskId) {
            await refreshResolvedMonitorBranches()
        }
        .sheet(isPresented: $showProgress) {
            CloneProgressSheet()
                .environment(jobs)
        }
        .sheet(isPresented: $pendingBranchSwitch) {
            BranchSwitchSheet(
                projects: selectedProjects,
                targetBranch: $branchSwitchTarget,
                baseBranches: $branchSwitchBaseDrafts,
                dirtyPolicy: $branchSwitchDirtyPolicy,
                onCancel: { pendingBranchSwitch = false },
                onRun: { triggerBranchSwitchFromSheet() }
            )
        }
        .sheet(item: $pendingMonitorProject) { project in
            MonitorBranchSheet(
                project: project,
                watches: $monitorWatchesDraft,
                onCancel: { pendingMonitorProject = nil },
                onSave: { saveMonitor(project) }
            )
        }
        .alert("确定要强制重新克隆吗?",
               isPresented: $pendingReclone,
               actions: {
                   Button("取消", role: .cancel) {}
                   Button("继续删除并重新克隆", role: .destructive) { runJob() }
               },
               message: {
                   let count = vm.selectedIds.count
                   Text("将删除 \(count) 个本地目录(若存在)后重新 clone。此操作不可恢复。")
               })
        .alert("确定丢弃所有未提交改动并继续吗?",
               isPresented: $pendingDiscardBranchSwitch,
               actions: {
                   Button("取消", role: .cancel) {}
                   Button("丢弃并继续", role: .destructive) { runBranchSwitch() }
               },
               message: {
                   Text("会对存在未提交改动的仓库执行 git reset --hard 和 git clean -fd，未提交改动不可恢复。")
               })
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("项目列表").font(.headline)
            Picker("实例", selection: Binding(
                get: { currentInstance?.id ?? UUID() },
                set: { currentInstanceId = $0 }
            )) {
                ForEach(settings.config.instances) { inst in
                    Text(inst.name).tag(inst.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            TextField("搜索…", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Spacer()
            if let id = currentInstance?.id, store.loading[id] == true {
                ProgressView().controlSize(.small)
            }
            Button("⟳ 刷新列表") { Task { await reload() } }
                .disabled(currentInstance == nil)
        }
        .padding(8)
        .glassPanel(cornerRadius: 16)
    }

    private var list: some View {
        let visible = vm.displayed(all: projects)
        return List {
            HStack {
                let allSelected = !visible.isEmpty &&
                    Set(visible.map(\.id)).isSubset(of: vm.selectedIds)
                Toggle(isOn: Binding(
                    get: { allSelected },
                    set: { _ in vm.toggleAll(in: visible) }
                )) {
                    Text("☑ 全选")
                }
                .toggleStyle(.checkbox)
                Text("已选 \(vm.selectedIds.count) / 共 \(visible.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }

            ForEach(visible) { project in
                HStack {
                    Toggle(isOn: Binding(
                        get: { vm.selectedIds.contains(project.id) },
                        set: { isOn in
                            if isOn { vm.selectedIds.insert(project.id) }
                            else { vm.selectedIds.remove(project.id) }
                        }
                    )) { EmptyView() }
                    .toggleStyle(.checkbox)
                    VStack(alignment: .leading) {
                        Text(project.pathWithNamespace)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(project.webURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    if let root = activeCloneRoot,
                       LocalRepoChecker.isCloned(
                            rootDirectory: root,
                            pathWithNamespace: project.pathWithNamespace) {
                        let branch = LocalRepoChecker.currentBranch(
                            rootDirectory: root,
                            pathWithNamespace: project.pathWithNamespace
                        )
                        Text("✅ 已克隆\(branch.map { " · 当前: \($0)" } ?? "")")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 260, alignment: .trailing)
                    } else {
                        Text("⚠ 未克隆")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .frame(width: 260, alignment: .trailing)
                    }
                    monitorControl(for: project)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("同步目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activeCloneRoot?.path(percentEncoded: false) ?? "未选择目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("选择目录…") {
                    chooseCloneRoot()
                }
                .disabled(currentInstance == nil || jobs.isRunning)
                Button("使用默认目录") {
                    selectedCloneRoot = nil
                }
                .disabled(selectedCloneRoot == nil || jobs.isRunning)
            }

            HStack {
                Picker("模式", selection: $vm.mode) {
                    ForEach(CloneMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer()
                if let monitorMessage {
                    Text(monitorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("批量切分支…") {
                    configureBranchSwitch()
                }
                .disabled(vm.selectedIds.isEmpty || jobs.isRunning || currentInstance == nil)
                Button("对选中项执行同步 →") {
                    triggerSync()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.selectedIds.isEmpty || jobs.isRunning || currentInstance == nil || activeCloneRoot == nil)
            }
        }
        .padding(8)
        .glassPanel(cornerRadius: 16)
    }

    // MARK: - Helpers

    private func reloadIfNeeded() {
        guard let inst = currentInstance,
              store.projects[inst.id] == nil else { return }
        Task { await reload() }
    }

    private func monitorControl(for project: GLProject) -> some View {
        let target = monitorTarget(for: project)
        return HStack(spacing: 6) {
            if let target {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(target.watches) { watch in
                        HStack(spacing: 4) {
                            if branchResolution(for: target, watch: watch) == .loading {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(monitorBranchText(for: target, watch: watch))
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                configureMonitor(project)
            } label: {
                Label(target == nil ? "配置分支" : "更新配置", systemImage: "eye")
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .frame(width: 390, alignment: .leading)
    }

    private var monitorResolutionTaskId: String {
        let instanceId = currentInstance?.id.uuidString ?? "none"
        let watchIds = settings.config.monitor.targets
            .filter { $0.instanceId == currentInstance?.id }
            .flatMap(\.watches)
            .map { "\($0.id.uuidString):\($0.selector.displayHint)" }
            .joined(separator: "|")
        return "\(instanceId)|\(watchIds)"
    }

    private func refreshResolvedMonitorBranches() async {
        guard let instance = currentInstance,
              let token = settings.token(for: instance.id)
        else {
            resolvedMonitorBranches = [:]
            return
        }

        let targets = settings.config.monitor.targets.filter { $0.instanceId == instance.id }
        let work = targets.flatMap { target in target.watches.map { (target, $0) } }
        resolvedMonitorBranches = Dictionary(uniqueKeysWithValues: work.map {
            ($0.0.statusId(for: $0.1), .loading)
        })

        let client = GitLabClient(instance: instance, token: token)
        await withTaskGroup(of: (String, MonitorBranchResolution).self) { group in
            for (target, watch) in work {
                group.addTask {
                    let resolver = BranchResolver { projectId, search in
                        try await client.listBranches(projectId: projectId, search: search)
                    }
                    let branch = try? await resolver.resolve(
                        selector: watch.selector,
                        projectId: target.projectId
                    )
                    let resolution = branch.map(MonitorBranchResolution.resolved) ?? .unavailable
                    return (target.statusId(for: watch), resolution)
                }
            }

            for await (statusId, resolution) in group {
                resolvedMonitorBranches[statusId] = resolution
            }
        }
    }

    private func branchResolution(for target: MonitorTarget, watch: MonitorBranchWatch) -> MonitorBranchResolution {
        if case .fixed(let branch) = watch.selector {
            return .resolved(branch)
        }
        return resolvedMonitorBranches[target.statusId(for: watch)] ?? .loading
    }

    private func monitorBranchText(for target: MonitorTarget, watch: MonitorBranchWatch) -> String {
        let branch: String
        switch branchResolution(for: target, watch: watch) {
        case .loading:
            branch = "解析中"
        case .resolved(let value):
            branch = value
        case .unavailable:
            branch = "未匹配"
        }
        let marker = watch.monitorEnabled ? "" : "（仅标记）"
        return "\(watch.role.displayName): \(branch)\(marker)"
    }

    private func monitorTarget(for project: GLProject) -> MonitorTarget? {
        settings.config.monitor.target(for: project)
    }

    private func defaultBaseBranch(for project: GLProject) -> String {
        if let selector = monitorTarget(for: project)?.productionWatch?.selector,
           case .fixed(let branch) = selector {
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return project.defaultBranch ?? "main"
    }

    private func configureMonitor(_ project: GLProject) {
        if let existing = monitorTarget(for: project)?.watches {
            monitorWatchesDraft = sortedMonitorWatches(existing)
        } else {
            monitorWatchesDraft = [
                MonitorBranchWatch(
                    selector: .fixed(project.defaultBranch ?? "main"),
                    role: .production,
                    monitorEnabled: false
                )
            ]
        }
        pendingMonitorProject = project
    }

    private func saveMonitor(_ project: GLProject) {
        let watches = sanitizedMonitorWatches(monitorWatchesDraft)
        do {
            if watches.isEmpty {
                if let target = monitorTarget(for: project) {
                    try settings.removeMonitorTarget(id: target.id)
                }
                monitorMessage = "已关闭 \(project.pathWithNamespace) 的 CI/CD 观测"
            } else {
                try settings.upsertMonitorTarget(project: project, watches: watches)
                let label = watches
                    .map { "\($0.role.displayName): \($0.roleSummary)" }
                    .joined(separator: ", ")
                monitorMessage = "已保存 \(project.pathWithNamespace) @ \(label)"
            }
            pendingMonitorProject = nil
        } catch {
            monitorMessage = error.localizedDescription
        }
    }

    private func sanitizedMonitorWatches(_ source: [MonitorBranchWatch]) -> [MonitorBranchWatch] {
        sortedMonitorWatches(source).filter { !$0.selector.displayHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func sortedMonitorWatches(_ source: [MonitorBranchWatch]) -> [MonitorBranchWatch] {
        let roleOrder: [MonitorBranchRole: Int] = [
            .production: 0,
            .testing: 1,
            .custom: 2
        ]
        return source.sorted {
            (roleOrder[$0.role] ?? 9, $0.id.uuidString) <
                (roleOrder[$1.role] ?? 9, $1.id.uuidString)
        }
    }

    @MainActor
    private func reload() async {
        guard let inst = currentInstance,
              let token = settings.token(for: inst.id)
        else { return }
        await store.reload(instance: inst, token: token)
    }

    private func chooseCloneRoot() {
        let panel = NSOpenPanel()
        panel.title = "选择同步目录"
        panel.prompt = "选择"
        panel.message = "项目会按 namespace/path 克隆或拉取到此目录下。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let root = activeCloneRoot {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            selectedCloneRoot = url
        }
    }

    // MARK: - Sync

    private func triggerSync() {
        guard let inst = currentInstance,
              settings.token(for: inst.id) != nil else { return }
        let chosen = selectedProjects
        guard !chosen.isEmpty else { return }
        if vm.mode == .reclone {
            pendingReclone = true
        } else {
            runJob()
        }
    }

    private func runJob() {
        guard let inst = currentInstance,
              let rootDirectory = activeCloneRoot else { return }
        let chosen = selectedProjects
        guard !chosen.isEmpty else { return }
        showProgress = true
        let coord = BulkSyncCoordinator(
            settings: settings, projects: store, jobs: jobs
        )
        Task {
            await coord.sync(
                in: inst,
                mode: vm.mode,
                projectsToSync: chosen,
                rootDirectory: rootDirectory
            )
        }
    }

    // MARK: - Branch switch

    private func configureBranchSwitch() {
        let chosen = selectedProjects
        guard !chosen.isEmpty else { return }
        if branchSwitchTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            branchSwitchTarget = "feature/"
        }
        branchSwitchDirtyPolicy = .skip
        Task {
            branchSwitchBaseDrafts = await resolvedProductionBaseBranches(for: chosen)
            pendingBranchSwitch = true
        }
    }

    private func resolvedProductionBaseBranches(for projects: [GLProject]) async -> [Int: String] {
        var drafts = Dictionary(uniqueKeysWithValues:
            projects.map { ($0.id, defaultBaseBranch(for: $0)) }
        )
        guard let inst = currentInstance,
              let token = settings.token(for: inst.id) else { return drafts }
        let client = GitLabClient(instance: inst, token: token)
        let resolver = ProductionBranchResolver(monitor: settings.config.monitor) { projectId, search in
            try await client.listBranches(projectId: projectId, search: search)
        }
        let resolved = await resolver.resolve(projects: projects)
        for (projectId, branch) in resolved {
            drafts[projectId] = branch
        }
        return drafts
    }

    private func triggerBranchSwitchFromSheet() {
        if branchSwitchDirtyPolicy == .discard {
            pendingDiscardBranchSwitch = true
        } else {
            runBranchSwitch()
        }
    }

    private func runBranchSwitch() {
        guard let inst = currentInstance,
              let rootDirectory = activeCloneRoot else { return }
        let chosen = selectedProjects
        guard !chosen.isEmpty else { return }
        pendingBranchSwitch = false
        showProgress = true
        let coord = BulkBranchSwitchCoordinator(settings: settings, jobs: jobs)
        Task {
            await coord.switchBranches(
                in: inst,
                projectsToSwitch: chosen,
                targetBranch: branchSwitchTarget,
                baseBranches: branchSwitchBaseDrafts,
                dirtyPolicy: branchSwitchDirtyPolicy,
                rootDirectory: rootDirectory
            )
        }
    }
}

private enum MonitorBranchResolution: Equatable {
    case loading
    case resolved(String)
    case unavailable
}

private struct BranchSwitchSheet: View {
    let projects: [GLProject]
    @Binding var targetBranch: String
    @Binding var baseBranches: [Int: String]
    @Binding var dirtyPolicy: DirtyWorktreePolicy
    let onCancel: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量切分支")
                .font(.headline)

            Form {
                TextField("目标分支", text: $targetBranch)
                    .textFieldStyle(.roundedBorder)

                Picker("未提交改动", selection: $dirtyPolicy) {
                    ForEach(DirtyWorktreePolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                Text(dirtyPolicy.warningText)
                    .font(.caption)
                    .foregroundStyle(dirtyPolicy == .discard ? .red : .secondary)
            }
            .frame(height: 112)
            .scrollContentBackground(.hidden)
            .glassPanel(cornerRadius: 16)

            Text("基准分支")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(projects) { project in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.pathWithNamespace)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("将从 origin/\(baseBranches[project.id] ?? project.defaultBranch ?? "main") 新建并签出目标分支，并设置 upstream")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            TextField("基准分支", text: Binding(
                                get: { baseBranches[project.id] ?? project.defaultBranch ?? "main" },
                                set: { baseBranches[project.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 180)
            .glassPanel(cornerRadius: 16, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            HStack {
                Text("已选 \(projects.count) 个项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { onCancel() }
                Button("开始切分支") { onRun() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 640)
        .frame(minHeight: 420)
        .frostedWindowBackground()
    }
}

private struct MonitorBranchSheet: View {
    let project: GLProject
    @Binding var watches: [MonitorBranchWatch]
    let onCancel: () -> Void
    let onSave: () -> Void
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置项目分支")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.pathWithNamespace)
                    .font(.body)
            Text(project.webURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .glassPanel(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 8) {
                BranchRoleEditor(
                    title: MonitorBranchRole.production.displayName,
                    isEnabled: enabledBinding(
                        role: .production,
                        fallback: .fixed(project.defaultBranch ?? "main")
                    ),
                    selector: selectorBinding(
                        role: .production,
                        fallback: .fixed(project.defaultBranch ?? "main")
                    ),
                    monitorEnabled: monitorEnabledBinding(role: .production, fallback: false),
                    ciSelector: ciSelectorBinding(
                        role: .production,
                        fallback: .rule(prefix: "release", separator: "-", format: .yyyymmddWithTail)
                    ),
                    ciSelectorEnabled: ciSelectorEnabledBinding(
                        role: .production,
                        fallback: .rule(prefix: "release", separator: "-", format: .yyyymmddWithTail)
                    ),
                    previewContext: previewContext
                )

                BranchRoleEditor(
                    title: MonitorBranchRole.testing.displayName,
                    isEnabled: enabledBinding(
                        role: .testing,
                        fallback: .rule(prefix: "test", separator: "", format: .yyyymmdd)
                    ),
                    selector: selectorBinding(
                        role: .testing,
                        fallback: .rule(prefix: "test", separator: "", format: .yyyymmdd)
                    ),
                    monitorEnabled: monitorEnabledBinding(role: .testing, fallback: true),
                    ciSelector: ciSelectorBinding(
                        role: .testing,
                        fallback: .rule(prefix: "test", separator: "", format: .yyyymmdd)
                    ),
                    ciSelectorEnabled: ciSelectorEnabledBinding(
                        role: .testing,
                        fallback: .rule(prefix: "test", separator: "", format: .yyyymmdd)
                    ),
                    previewContext: previewContext
                )

                ForEach($watches) { $watch in
                    if watch.role == .custom {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(MonitorBranchRole.custom.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                BranchSelectorEditor(selector: $watch.selector, previewContext: previewContext)
                                Toggle("监测运行状态", isOn: $watch.monitorEnabled)
                                    .toggleStyle(.checkbox)
                                    .font(.caption2)
                            }

                            Button {
                                watches.removeAll { $0.id == watch.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    watches.append(MonitorBranchWatch(selector: .fixed(project.defaultBranch ?? "main"), role: .custom))
                } label: {
                    Label("添加其他分支", systemImage: "plus.circle")
                }
            }
            .glassPanel(cornerRadius: 16)

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                Button("保存配置") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .frostedWindowBackground()
    }

    private func enabledBinding(role: MonitorBranchRole, fallback: BranchSelector) -> Binding<Bool> {
        Binding(
            get: {
                watches.contains { $0.role == role }
            },
            set: { isEnabled in
                if isEnabled {
                    if !watches.contains(where: { $0.role == role }) {
                        watches.append(MonitorBranchWatch(
                            selector: fallback,
                            role: role,
                            monitorEnabled: defaultMonitorEnabled(for: role)
                        ))
                    }
                } else {
                    watches.removeAll { $0.role == role }
                }
            }
        )
    }

    private func selectorBinding(role: MonitorBranchRole, fallback: BranchSelector) -> Binding<BranchSelector> {
        Binding(
            get: {
                watches.first(where: { $0.role == role })?.selector ?? fallback
            },
            set: { newSelector in
                if let index = watches.firstIndex(where: { $0.role == role }) {
                    watches[index].selector = newSelector
                } else {
                    watches.append(MonitorBranchWatch(
                        selector: newSelector,
                        role: role,
                        monitorEnabled: defaultMonitorEnabled(for: role)
                    ))
                }
            }
        )
    }

    private func monitorEnabledBinding(role: MonitorBranchRole, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: {
                watches.first(where: { $0.role == role })?.monitorEnabled ?? fallback
            },
            set: { isEnabled in
                if let index = watches.firstIndex(where: { $0.role == role }) {
                    watches[index].monitorEnabled = isEnabled
                }
            }
        )
    }

    private func ciSelectorBinding(role: MonitorBranchRole, fallback: BranchSelector) -> Binding<BranchSelector> {
        Binding(
            get: {
                watches.first(where: { $0.role == role })?.ciSelector ?? fallback
            },
            set: { newSelector in
                if let index = watches.firstIndex(where: { $0.role == role }) {
                    watches[index].ciSelector = newSelector
                }
            }
        )
    }

    private func ciSelectorEnabledBinding(role: MonitorBranchRole, fallback: BranchSelector) -> Binding<Bool> {
        Binding(
            get: {
                watches.first(where: { $0.role == role })?.ciSelector != nil
            },
            set: { isEnabled in
                if let index = watches.firstIndex(where: { $0.role == role }) {
                    watches[index].ciSelector = isEnabled ? fallback : nil
                }
            }
        )
    }

    private var previewContext: BranchMatchPreviewContext? {
        guard let instance = settings.config.instances.first(where: { $0.id == project.instanceId }),
              let token = settings.token(for: instance.id),
              !token.isEmpty else { return nil }
        return BranchMatchPreviewContext(instance: instance, token: token, projectId: project.id)
    }

    private func defaultMonitorEnabled(for role: MonitorBranchRole) -> Bool {
        role != .production
    }
}

struct BranchMatchPreviewContext: Equatable {
    let instance: GitLabInstance
    let token: String
    let projectId: Int
}

private struct RegexPatternPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let pattern: String
}

private struct BranchRoleEditor: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var selector: BranchSelector
    @Binding var monitorEnabled: Bool
    @Binding var ciSelector: BranchSelector
    @Binding var ciSelectorEnabled: Bool
    let previewContext: BranchMatchPreviewContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
            if isEnabled {
                BranchSelectorEditor(selector: $selector, previewContext: previewContext)
                Toggle("监测运行状态", isOn: $monitorEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                if monitorEnabled {
                    Toggle("CI/CD 使用其他分支或规则", isOn: $ciSelectorEnabled)
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                    if ciSelectorEnabled {
                        BranchSelectorEditor(selector: $ciSelector, previewContext: previewContext)
                    }
                }
            }
        }
    }
}

struct BranchSelectorEditor: View {
    @Binding var selector: BranchSelector
    var previewContext: BranchMatchPreviewContext? = nil

    private enum Mode: String, CaseIterable, Identifiable {
        case fixed = "固定分支"
        case rule = "动态匹配最新"
        case regex = "自定义正则"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .fixed
    @State private var fixedBranch = "main"
    @State private var rulePrefix = "test"
    @State private var ruleSeparator = ""
    @State private var ruleFormat: BranchDateFormat = .yyyymmdd
    @State private var regexPattern = "^test-\\d{8}$"
    @State private var selectedRegexPresetId = "testDashDate"
    @State private var matchedBranch: String?
    @State private var previewMessage: String?
    @State private var isResolvingPreview = false

    private static let customRegexPresetId = "custom"
    private static let regexPresets: [RegexPatternPreset] = [
        RegexPatternPreset(id: "testDate", title: "testYYYYMMDD", pattern: "^test\\d{8}$"),
        RegexPatternPreset(id: "testDashDate", title: "test-YYYYMMDD", pattern: "^test-\\d{8}$"),
        RegexPatternPreset(id: "stagingAny", title: "staging 开头", pattern: "^staging.*$"),
        RegexPatternPreset(id: "releaseDateTail", title: "release-YYYYMMDD-尾缀", pattern: "^release-\\d{8}-.+$"),
        RegexPatternPreset(id: "versionTag", title: "v1.2.3", pattern: "^v\\d+\\.\\d+\\.\\d+$")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker("类型", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .fixed:
                TextField("分支名", text: $fixedBranch)
                    .textFieldStyle(.roundedBorder)
            case .rule:
                HStack {
                    TextField("前缀", text: $rulePrefix)
                        .textFieldStyle(.roundedBorder)
                    TextField("分隔符", text: $ruleSeparator)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Picker("", selection: $ruleFormat) {
                        ForEach(BranchDateFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Text("匹配示例: \(exampleBranch)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .regex:
                HStack(spacing: 8) {
                    Text("常用模板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("常用模板", selection: $selectedRegexPresetId) {
                        Text("自定义").tag(Self.customRegexPresetId)
                        ForEach(Self.regexPresets) { preset in
                            Text(preset.title).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    Spacer()
                }
                TextField("^test-\\d{8}$", text: $regexPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Text("不会写正则可以先选模板，再按需调整。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if shouldShowPreview {
                matchPreviewLine
            }
        }
        .onAppear { syncFromSelector() }
        .onChange(of: mode) { _, _ in publish() }
        .onChange(of: fixedBranch) { _, _ in publish() }
        .onChange(of: rulePrefix) { _, _ in publish() }
        .onChange(of: ruleSeparator) { _, _ in publish() }
        .onChange(of: ruleFormat) { _, _ in publish() }
        .onChange(of: regexPattern) { _, _ in
            syncRegexPresetSelection()
            publish()
        }
        .onChange(of: selectedRegexPresetId) { _, newValue in
            guard let preset = Self.regexPresets.first(where: { $0.id == newValue }) else { return }
            regexPattern = preset.pattern
        }
        .task(id: previewKey) {
            await resolvePreview()
        }
    }

    private var matchPreviewLine: some View {
        HStack(spacing: 6) {
            if isResolvingPreview {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }
            Text(previewText)
                .font(.caption2)
                .foregroundStyle(previewColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var previewText: String {
        if isResolvingPreview {
            return mode == .fixed ? "正在检查固定分支是否存在..." : "正在匹配实际 git 分支..."
        }
        if let matchedBranch {
            return mode == .fixed ? "固定分支存在: \(matchedBranch)" : "实际匹配的 git 分支: \(matchedBranch)"
        }
        if let previewMessage { return previewMessage }
        return mode == .fixed ? "固定分支不存在" : "实际匹配的 git 分支: 未匹配"
    }

    private var previewColor: Color {
        matchedBranch == nil ? .red : .secondary
    }

    private var shouldShowPreview: Bool {
        mode != .fixed || previewContext != nil
    }

    private var previewKey: String {
        switch mode {
        case .fixed:
            return "fixed|\(fixedBranch)|\(previewContext?.instance.id.uuidString ?? "")|\(previewContext?.projectId ?? -1)"
        case .rule:
            return "rule|\(rulePrefix)|\(ruleSeparator)|\(ruleFormat.rawValue)|\(previewContext?.instance.id.uuidString ?? "")|\(previewContext?.projectId ?? -1)"
        case .regex:
            return "regex|\(regexPattern)|\(selectedRegexPresetId)|\(previewContext?.instance.id.uuidString ?? "")|\(previewContext?.projectId ?? -1)"
        }
    }

    private var exampleBranch: String {
        let prefix = rulePrefix.isEmpty ? "test" : rulePrefix
        let head = "\(prefix)\(ruleSeparator)"
        switch ruleFormat {
        case .yyyymmdd: return "\(head)20260525"
        case .yyyymmddDashed: return "\(head)2026-05-25"
        case .yyyymmddDotted: return "\(head)2026.05.25"
        case .yyyymmddWithTail: return "\(head)20260525-hotfix"
        }
    }

    private func syncFromSelector() {
        switch selector {
        case .fixed(let branch):
            mode = .fixed
            fixedBranch = branch
        case .rule(let prefix, let separator, let format):
            mode = .rule
            rulePrefix = prefix
            ruleSeparator = separator
            ruleFormat = format
        case .regex(let pattern):
            mode = .regex
            regexPattern = pattern
            syncRegexPresetSelection()
        }
    }

    private func publish() {
        switch mode {
        case .fixed:
            selector = .fixed(fixedBranch)
        case .rule:
            selector = .rule(prefix: rulePrefix, separator: ruleSeparator, format: ruleFormat)
        case .regex:
            selector = .regex(regexPattern)
        }
    }

    @MainActor
    private func resolvePreview() async {
        guard let previewContext else {
            matchedBranch = nil
            previewMessage = "实际匹配的 git 分支: 缺少 GitLab 实例或 PAT"
            isResolvingPreview = false
            return
        }

        let currentSelector = selectorForPreview
        if case .fixed(let branch) = currentSelector,
           branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matchedBranch = nil
            previewMessage = "固定分支名不能为空"
            isResolvingPreview = false
            return
        }
        if case .fixed = currentSelector {
            // 固定分支不需要正则校验。
        } else if currentSelector.compiledRegex == nil {
            matchedBranch = nil
            previewMessage = "实际匹配的 git 分支: 正则无效"
            isResolvingPreview = false
            return
        }

        isResolvingPreview = true
        matchedBranch = nil
        previewMessage = nil
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }

        do {
            let client = GitLabClient(instance: previewContext.instance, token: previewContext.token)
            let resolved: String?
            switch currentSelector {
            case .fixed(let branch):
                let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
                let branches = try await client.listBranches(projectId: previewContext.projectId, search: trimmed)
                resolved = branches.contains(where: { $0.name == trimmed }) ? trimmed : nil
            case .rule, .regex:
                let resolver = BranchResolver { projectId, search in
                    try await client.listBranches(projectId: projectId, search: search)
                }
                resolved = try await resolver.resolve(
                    selector: currentSelector,
                    projectId: previewContext.projectId
                )
            }
            if Task.isCancelled { return }
            matchedBranch = resolved
            if resolved == nil {
                previewMessage = mode == .fixed ? "固定分支不存在: \(fixedBranch)" : "实际匹配的 git 分支: 未匹配"
            } else {
                previewMessage = nil
            }
            isResolvingPreview = false
        } catch {
            if Task.isCancelled { return }
            matchedBranch = nil
            previewMessage = "实际匹配失败: \(error.localizedDescription)"
            isResolvingPreview = false
        }
    }

    private var selectorForPreview: BranchSelector {
        switch mode {
        case .fixed:
            return .fixed(fixedBranch)
        case .rule:
            return .rule(prefix: rulePrefix, separator: ruleSeparator, format: ruleFormat)
        case .regex:
            return .regex(regexPattern)
        }
    }

    private func syncRegexPresetSelection() {
        selectedRegexPresetId = Self.regexPresets.first(where: { $0.pattern == regexPattern })?.id
            ?? Self.customRegexPresetId
    }
}
