import SwiftUI

struct MenuBarPopover: View {
    let fatalLoadError: String?
    @Environment(SettingsStore.self) private var settings
    @Environment(ProjectStore.self) private var projects
    @Environment(CloneJobStore.self) private var jobs
    @Environment(PipelineMonitorStore.self) private var pipelineMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var defaultMode: CloneMode = .pull
    @State private var statusMessage: String?

    private var currentInstance: GitLabInstance? {
        if let id = settings.currentInstanceId,
           let inst = settings.config.instances.first(where: { $0.id == id }) {
            return inst
        }
        return settings.config.instances.first
    }

    private var monitorTargetsWithWatches: [MonitorTarget] {
        settings.config.monitor.targets.filter { target in
            target.watches.contains(where: \.monitorEnabled)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fatalLoadError {
                Text("配置加载失败: \(fatalLoadError)")
                    .foregroundStyle(.red).font(.caption)
            }

            HStack {
                Text("GitLabMenu").font(.headline)
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }

            if settings.config.instances.isEmpty {
                Text(MainDashboardCopy.emptyProjectHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                        Text(MainDashboardCopy.configureGitLabTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !settings.config.instances.isEmpty {
                Picker("实例", selection: Binding(
                    get: { settings.currentInstanceId ?? currentInstance?.id ?? UUID() },
                    set: { settings.currentInstanceId = $0 }
                )) {
                    ForEach(settings.config.instances) { inst in
                        Text(inst.name).tag(inst.id)
                    }
                }
                .labelsHidden()
            }

            pipelineSection
                .glassPanel(cornerRadius: 14, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

            actionSection
                .glassPanel(cornerRadius: 14, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

            if jobs.isRunning, let job = jobs.currentJob {
                progressSection(job: job)
                    .glassPanel(cornerRadius: 14, padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            } else if let s = statusMessage {
                Text(s).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            Button("退出 GitLabMenu") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 340)
        .frostedWindowBackground()
        .onAppear { defaultMode = settings.config.clone.defaultMode }
        .task(id: settings.config.monitor) {
            await monitorLoop()
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("默认模式", selection: $defaultMode) {
                ForEach(CloneMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await triggerSyncAll() }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("一键同步全部")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(currentInstance == nil || jobs.isRunning)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "project-list")
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("打开项目列表…")
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                openCloneRoot()
            } label: {
                HStack {
                    Image(systemName: "folder")
                    Text("打开克隆目录")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(currentInstance == nil)
        }
    }

    private func progressSection(job: CloneJob) -> some View {
        let total = job.projects.count
        let done = jobs.summary.success + jobs.summary.failed + jobs.summary.skipped
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("同步中", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(done)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
        }
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("运行情况", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await refreshMonitor() }
                } label: {
                    Image(systemName: pipelineMonitor.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(pipelineMonitor.isRefreshing || monitorTargetsWithWatches.isEmpty)
            }

            if monitorTargetsWithWatches.isEmpty {
                Text("暂无观测项目，可在项目列表中添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(monitorTargetsWithWatches) { target in
                        ForEach(target.watches.filter(\.monitorEnabled)) { watch in
                            PipelineStatusRow(
                                target: target,
                                watch: watch,
                                status: pipelineMonitor.statuses[target.statusId(for: watch)]
                            )
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func triggerSyncAll() async {
        guard let inst = currentInstance else { return }
        if defaultMode == .reclone {
            // Popover 内不便弹模态,提示用户走列表窗
            statusMessage = "强制重新克隆请到项目列表窗口确认后执行"
            return
        }
        let coord = BulkSyncCoordinator(
            settings: settings, projects: projects, jobs: jobs
        )
        let ok = await coord.sync(in: inst, mode: defaultMode)
        if !ok {
            statusMessage = "该实例下没有可同步的项目(可能未配置或拉取失败)"
        } else {
            statusMessage = nil
        }
    }

    private func openCloneRoot() {
        guard let inst = currentInstance else { return }
        try? FileManager.default.createDirectory(
            at: inst.defaultCloneRoot, withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([inst.defaultCloneRoot])
    }

    @MainActor
    private func refreshMonitor() async {
        await pipelineMonitor.refreshAll(config: settings.config) { id in
            settings.token(for: id)
        }
    }

    private func monitorLoop() async {
        guard !monitorTargetsWithWatches.isEmpty else { return }
        await refreshMonitor()
        let interval = max(settings.config.monitor.pollIntervalSeconds, 30)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            if !Task.isCancelled {
                await refreshMonitor()
            }
        }
    }
}

private struct PipelineStatusRow: View {
    let target: MonitorTarget
    let watch: MonitorBranchWatch
    let status: PipelineMonitorStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill((status?.status ?? .unknown).statusColor)
                    .frame(width: 10, height: 10)
                if status?.isLoading == true {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.45)
                }
            }
            .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(target.pathWithNamespace)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text((status?.status ?? .unknown).displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle((status?.status ?? .unknown).statusColor)
                }

                HStack(spacing: 6) {
                    Label(watchLabel, systemImage: "arrow.triangle.branch")
                    if let updatedAt = status?.updatedAt {
                        Text(updatedAt, style: .relative)
                    }
                    if let webURL = status?.webURL {
                        Link("打开", destination: webURL)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if isInProgress, let startedAt = status?.startedAt {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        progressLine(now: context.date, startedAt: startedAt)
                    }
                }

                if let error = status?.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var branchLabel: String {
        status?.resolvedBranch ?? watch.selector.displayHint
    }

    private var watchLabel: String {
        switch watch.role {
        case .production, .testing:
            if let ciSelector = watch.ciSelector, ciSelector != watch.selector {
                return "\(watch.role.shortName): \(watch.selector.displayHint) -> CI/CD: \(branchLabel)"
            }
            return "\(watch.role.shortName): \(branchLabel)"
        case .custom:
            return branchLabel
        }
    }

    private var isInProgress: Bool {
        let value = status?.status ?? .unknown
        return value == .running || value == .pending
    }

    private func progressLine(now: Date, startedAt: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return HStack(spacing: 6) {
            if let baseline = status?.baselineDuration, baseline > 0 {
                ProgressView(value: min(elapsed / baseline, 1))
                    .frame(maxWidth: 110)
                    .tint(elapsed > baseline ? .orange : .blue)
                Text("\(format(elapsed)) / \(format(baseline))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("已运行 \(format(elapsed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let seconds = total % 60
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m\(seconds)s"
    }
}

private extension PipelineStatus {
    var statusColor: Color {
        switch self {
        case .success:
            return .green
        case .failed:
            return .red
        case .canceled, .skipped:
            return .secondary
        case .running:
            return .blue
        case .created, .waitingForResource, .preparing, .pending, .manual, .scheduled:
            return .orange
        case .unknown:
            return .gray
        }
    }
}
