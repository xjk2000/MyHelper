import AppKit
import SwiftUI

public enum GitLabPipelineState: String, Equatable, Sendable {
    case success
    case failed
    case running
    case pending
    case canceled
    case skipped
    case unknown
}

public struct GitLabPipelineSummary: Identifiable, Sendable {
    public let id: String
    public let projectName: String
    public let pathWithNamespace: String
    public let branch: String
    public let role: String
    public let state: GitLabPipelineState
    public let webURL: URL?
    public let updatedAt: Date?
    public let errorMessage: String?
}

public struct GitLabPipelineOverview: Sendable {
    public let items: [GitLabPipelineSummary]
    public let configuredWatchCount: Int
    public let refreshedAt: Date
    public let errorMessage: String?

    public static let empty = GitLabPipelineOverview(
        items: [],
        configuredWatchCount: 0,
        refreshedAt: .distantPast,
        errorMessage: nil
    )
}

public enum GitLabMenuPlugin {
    @MainActor
    @discardableResult
    public static func openMainWindow() -> Bool {
        PluginRuntime.shared.prepareIfNeeded()
        PluginRuntime.shared.showMainWindow()
        return true
    }

    @MainActor
    public static func loadPipelineOverview() async -> GitLabPipelineOverview {
        await PluginRuntime.shared.loadPipelineOverview()
    }
}

@MainActor
private final class PluginRuntime {
    static let shared = PluginRuntime()

    private var settings: SettingsStore?
    private var projects: ProjectStore?
    private var cloneJobs: CloneJobStore?
    private var pipelineMonitor: PipelineMonitorStore?
    private var fatalLoadError: String?
    private var mainWindow: NSWindow?

    private init() {}

    func prepareIfNeeded() {
        guard settings == nil else { return }

        do {
            try AppPaths.ensureSupportDirectoryExists()
            settings = try SettingsStore()
            fatalLoadError = nil
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitlab-menu-plugin-fallback.json")
            settings = try? SettingsStore(
                configFile: ConfigFile(url: fallbackURL),
                keychain: KeychainHelper(service: "GitLabMenu")
            )
            fatalLoadError = error.localizedDescription
        }

        projects = ProjectStore()
        cloneJobs = CloneJobStore()
        pipelineMonitor = PipelineMonitorStore()
    }

    func showMainWindow() {
        guard let settings, let projects, let cloneJobs, let pipelineMonitor else {
            return
        }

        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitLab 工具"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: GitLabPluginRootView(fatalLoadError: fatalLoadError)
                    .environment(settings)
                    .environment(projects)
                    .environment(cloneJobs)
                    .environment(pipelineMonitor)
            )
            window.center()
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func loadPipelineOverview() async -> GitLabPipelineOverview {
        prepareIfNeeded()
        guard let settings, let pipelineMonitor else {
            return GitLabPipelineOverview(
                items: [],
                configuredWatchCount: 0,
                refreshedAt: Date(),
                errorMessage: fatalLoadError ?? "GitLab 配置不可用"
            )
        }

        let configuredWatches = settings.config.monitor.targets.flatMap { target in
            target.watches.filter(\.monitorEnabled).map { (target, $0) }
        }
        guard !configuredWatches.isEmpty else {
            return GitLabPipelineOverview(
                items: [],
                configuredWatchCount: 0,
                refreshedAt: Date(),
                errorMessage: nil
            )
        }

        await pipelineMonitor.refreshAll(config: settings.config) { instanceId in
            settings.token(for: instanceId)
        }

        let items = configuredWatches.map { target, watch in
            let status = pipelineMonitor.statuses[target.statusId(for: watch)]
            return GitLabPipelineSummary(
                id: target.statusId(for: watch),
                projectName: target.name,
                pathWithNamespace: target.pathWithNamespace,
                branch: status?.resolvedBranch ?? watch.pipelineSelector.displayHint,
                role: watch.role.shortName,
                state: publicState(for: status?.status ?? .unknown),
                webURL: status?.webURL,
                updatedAt: status?.updatedAt,
                errorMessage: status?.errorMessage
            )
        }

        return GitLabPipelineOverview(
            items: items,
            configuredWatchCount: configuredWatches.count,
            refreshedAt: Date(),
            errorMessage: nil
        )
    }

    private func publicState(for status: PipelineStatus) -> GitLabPipelineState {
        switch status {
        case .success:
            return .success
        case .failed:
            return .failed
        case .running:
            return .running
        case .canceled:
            return .canceled
        case .skipped:
            return .skipped
        case .created, .waitingForResource, .preparing, .pending, .manual, .scheduled:
            return .pending
        case .unknown:
            return .unknown
        }
    }
}

private struct GitLabPluginRootView: View {
    let fatalLoadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let fatalLoadError {
                Text("配置加载失败：\(fatalLoadError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            MainDashboardWindow()
        }
    }
}
