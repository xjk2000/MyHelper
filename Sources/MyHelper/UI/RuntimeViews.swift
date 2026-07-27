import AppKit
import GitLabMenuPlugin
import MindAnchorPlugin
import SwiftUI
import TwoFAPlugin

struct RuntimeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    let selected: RuntimeScope
    let scopes: [RuntimeScope]
    let language: WidgetLanguage
    let onSelect: (RuntimeScope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(scopes) { scope in
                Button {
                    onSelect(scope)
                } label: {
                    HStack(spacing: 6) {
                        RuntimeLogoView(scope: scope, size: 16)
                        Text(label(for: scope))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selected == scope ? .primary : .secondary)
                    .frame(minWidth: scope == .claudeCode ? 124 : 88, minHeight: 30)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected == scope ? WidgetPalette.controlSelectedFill(colorScheme) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(label(for: scope))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private func label(for scope: RuntimeScope) -> String {
        switch scope {
        case .codex:
            return "Codex"
        case .claudeCode:
            return language.text("Claude Code", "Claude Code")
        }
    }
}

struct RuntimeStatusMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @State private var selectedPage: RuntimeStatusMenuPage = .usage
    @State private var gitLabOverview = GitLabPipelineOverview.empty
    @State private var twoFAOverview = TwoFAMenuOverview.empty
    @State private var isRefreshingGitLab = false
    let openRuntime: (RuntimeScope) -> Void
    let openTool: (HelperTool) -> Void
    let openCurrent: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    let updatePopoverHeight: (CGFloat) -> Void

    private var language: WidgetLanguage { settings.language }
    private var displayedScopes: [RuntimeScope] { settings.visibleRuntimeScopes }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pageSwitcher
            Group {
                switch selectedPage {
                case .usage:
                    VStack(spacing: 9) {
                        ForEach(displayedScopes) { scope in
                            RuntimeSummaryCard(
                                summary: summary(for: scope),
                                isSelected: store.selectedRuntimeScope == scope,
                                language: language
                            ) {
                                openRuntime(scope)
                            }
                        }
                    }
                    totalRow
                    twoFASection
                    gitLabPipelineSection
                case .tools:
                    menuToolsSection
                case .sprint:
                    MindAnchorPlugin.makeSprintMenuView()
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 380, height: currentPopoverHeight, alignment: .top)
        .task {
            await refreshGitLabPipelines()
            refreshTwoFAOverview()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            guard selectedPage == .usage else { return }
            refreshTwoFAOverview(at: date)
        }
        .onAppear {
            refreshTwoFAOverview()
            updatePopoverHeight(currentPopoverHeight)
        }
        .onChange(of: selectedPage) { _, _ in
            updatePopoverHeight(currentPopoverHeight)
        }
        .onChange(of: displayedScopes.count) { _, _ in
            updatePopoverHeight(currentPopoverHeight)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("MyHelper")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(language.text("刷新", "Refreshed")) \(runtimeTimeOnly(store.snapshot.refreshedAt))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
                Task { await refreshGitLabPipelines() }
            } label: {
                Image(systemName: store.isRefreshing || isRefreshingGitLab ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help(language.text("刷新", "Refresh"))
        }
    }

    private var pageSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(RuntimeStatusMenuPage.allCases) { page in
                Button {
                    selectedPage = page
                } label: {
                    Label(page.title(language), systemImage: page.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selectedPage == page ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedPage == page ? WidgetPalette.controlSelectedFill(colorScheme) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private var totalRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sum")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(language.text("今日总 token", "Total tokens today"))
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(runtimeFormatTokens(store.totalTodayTokens(for: displayedScopes)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private var twoFASection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.statusWarning)
                Text("2FA")
                    .font(.system(size: 11, weight: .semibold))
                if twoFAOverview.accountCount > 0 {
                    Text("\(twoFAOverview.accountCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(twoFAStatusSummary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    openTool(HelperToolRegistry.twoFA)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(language.text("打开 2FA 验证器", "Open 2FA authenticator"))
            }

            Group {
                if twoFAOverview.items.isEmpty {
                    GitLabPipelineEmptyState(
                        systemName: "key",
                        text: language.text("暂无 2FA 账号", "No 2FA accounts")
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: twoFAOverview.items.count > 3) {
                        LazyVStack(spacing: 5) {
                            ForEach(twoFAOverview.items) { item in
                                TwoFACompactRow(item: item, language: language) {
                                    if TwoFAPlugin.copyCode(accountID: item.id) {
                                        refreshTwoFAOverview()
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: twoFAListHeight)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private var twoFAStatusSummary: String {
        guard !twoFAOverview.items.isEmpty else {
            return ""
        }
        let minimumRemaining = twoFAOverview.items.map(\.remainingSeconds).min() ?? 0
        return language.text("最短剩余 \(minimumRemaining) 秒", "\(minimumRemaining)s min")
    }

    private var twoFAListHeight: CGFloat {
        min(CGFloat(twoFAOverview.items.count) * 40 + CGFloat(max(twoFAOverview.items.count - 1, 0)) * 5, 132)
    }

    private var gitLabPipelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.statusInfo)
                Text("GitLab CI/CD")
                    .font(.system(size: 11, weight: .semibold))
                if gitLabOverview.configuredWatchCount > 0 {
                    Text("\(gitLabOverview.configuredWatchCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(gitLabStatusSummary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    openTool(HelperToolRegistry.gitLabMenu)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(language.text("打开 GitLab 工具", "Open GitLab tools"))
            }

            Group {
                if isRefreshingGitLab && gitLabOverview.items.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(language.text("正在读取流水线状态", "Loading pipeline status"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                } else if let error = gitLabOverview.errorMessage, !error.isEmpty {
                    GitLabPipelineEmptyState(
                        systemName: "exclamationmark.triangle",
                        text: error
                    )
                } else if gitLabOverview.items.isEmpty {
                    GitLabPipelineEmptyState(
                        systemName: "point.3.connected.trianglepath.dotted",
                        text: language.text("暂无已启用的流水线监控", "No enabled pipeline monitors")
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: gitLabOverview.items.count > 3) {
                        LazyVStack(spacing: 5) {
                            ForEach(gitLabOverview.items) { item in
                                GitLabPipelineCompactRow(item: item, language: language)
                            }
                        }
                    }
                    .frame(height: 132)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private var gitLabStatusSummary: String {
        let running = gitLabOverview.items.filter { $0.state == .running || $0.state == .pending }.count
        let failed = gitLabOverview.items.filter { $0.state == .failed }.count
        if failed > 0 {
            return language.text("\(failed) 失败", "\(failed) failed")
        }
        if running > 0 {
            return language.text("\(running) 进行中", "\(running) active")
        }
        let success = gitLabOverview.items.filter { $0.state == .success }.count
        return success > 0 ? language.text("\(success) 正常", "\(success) healthy") : ""
    }

    private var currentPopoverHeight: CGFloat {
        switch selectedPage {
        case .usage:
            return runtimeStatusPopoverHeight(for: displayedScopes.count)
        case .tools:
            return runtimeToolsPopoverHeight(for: displayedScopes.count)
        case .sprint:
            return runtimeSprintPopoverHeight()
        }
    }

    @MainActor
    private func refreshGitLabPipelines() async {
        guard !isRefreshingGitLab else { return }
        isRefreshingGitLab = true
        gitLabOverview = await GitLabMenuPlugin.loadPipelineOverview()
        isRefreshingGitLab = false
    }

    @MainActor
    private func refreshTwoFAOverview(at date: Date = Date()) {
        twoFAOverview = TwoFAPlugin.menuOverview(at: date)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            menuCommandButton(
                title: language.text("打开主界面", "Open"),
                systemName: "rectangle.on.rectangle",
                action: openCurrent
            )
            menuCommandButton(
                title: language.text("设置", "Settings"),
                systemName: "gearshape",
                action: openSettings
            )
            menuCommandButton(
                title: language.text("退出", "Quit"),
                systemName: "power",
                action: quit
            )
        }
    }

    private var menuToolsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(language.text("工具插件", "Tool plugins"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(language.text("\(HelperToolRegistry.allTools.count) 个工具", "\(HelperToolRegistry.allTools.count) tools"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: HelperToolRegistry.allTools.count > 2) {
                LazyVStack(spacing: 8) {
                    ForEach(HelperToolRegistry.allTools) { tool in
                        RuntimeToolCard(tool: tool, language: language) {
                            openTool(tool)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: menuToolsSectionHeight, maxHeight: menuToolsSectionHeight, alignment: .topLeading)
    }

    private func menuCommandButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WidgetPalette.controlFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func summary(for scope: RuntimeScope) -> RuntimeMenuSummary {
        store.runtimeSnapshot(for: scope)?.summary ?? RuntimeMenuSummary(
            scope: scope,
            displayName: scope.displayName,
            status: .unavailable,
            fiveHourRemainingPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayRemainingPercent: nil,
            sevenDayResetsAt: nil,
            todayTokens: nil,
            sourceLabel: language.text("等待本机统计", "Waiting for local records")
        )
    }
}

private struct TwoFACompactRow: View {
    let item: TwoFAMenuItem
    let language: WidgetLanguage
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 8) {
                Image(systemName: item.isSelected ? "star.fill" : "key.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.statusWarning)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(WidgetPalette.statusWarning.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.accountName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        ProgressView(value: item.progress)
                            .frame(width: 58)
                        Text(language.text("剩余 \(item.remainingSeconds) 秒", "\(item.remainingSeconds)s left"))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(item.code)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text("复制 \(item.accountName) 的 2FA 验证码", "Copy 2FA code for \(item.accountName)"))
    }
}

private struct GitLabPipelineCompactRow: View {
    let item: GitLabPipelineSummary
    let language: WidgetLanguage

    var body: some View {
        Group {
            if let url = item.webURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .help(language.text("打开 GitLab Pipeline", "Open GitLab pipeline"))
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSystemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 18, height: 18)
                .background(Circle().fill(statusColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.projectName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(item.errorMessage == nil ? .secondary : WidgetPalette.statusDanger)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                if let updatedAt = item.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        if let error = item.errorMessage, !error.isEmpty {
            return error
        }
        return "\(item.role) · \(item.branch)"
    }

    private var statusTitle: String {
        switch item.state {
        case .success:
            return language.text("成功", "Success")
        case .failed:
            return language.text("失败", "Failed")
        case .running:
            return language.text("运行中", "Running")
        case .pending:
            return language.text("等待中", "Pending")
        case .canceled:
            return language.text("已取消", "Canceled")
        case .skipped:
            return language.text("已跳过", "Skipped")
        case .unknown:
            return language.text("未知", "Unknown")
        }
    }

    private var statusSystemName: String {
        switch item.state {
        case .success:
            return "checkmark"
        case .failed:
            return "xmark"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .pending:
            return "clock"
        case .canceled:
            return "slash.circle"
        case .skipped:
            return "forward"
        case .unknown:
            return "questionmark"
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .success:
            return WidgetPalette.statusSuccess
        case .failed:
            return WidgetPalette.statusDanger
        case .running:
            return WidgetPalette.statusInfo
        case .pending:
            return WidgetPalette.statusWarning
        case .canceled, .skipped, .unknown:
            return .secondary
        }
    }
}

private struct GitLabPipelineEmptyState: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private enum RuntimeStatusMenuPage: String, CaseIterable, Identifiable {
    case usage
    case tools
    case sprint

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .usage:
            return "chart.bar.xaxis"
        case .tools:
            return "square.grid.2x2"
        case .sprint:
            return "rectangle.3.group"
        }
    }

    func title(_ language: WidgetLanguage) -> String {
        switch self {
        case .usage:
            return language.text("用量", "Usage")
        case .tools:
            return language.text("工具", "Tools")
        case .sprint:
            return "Sprint"
        }
    }
}

private let menuToolsSectionHeight: CGFloat = 188

struct RuntimeToolCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let tool: HelperTool
    let language: WidgetLanguage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tool.tint)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tool.tint.opacity(0.13))
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(tool.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(tool.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(tool.detail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tool.tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tool.tint.opacity(0.11)))
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WidgetPalette.cardFill(colorScheme, elevated: true))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(WidgetPalette.cardStroke(colorScheme, elevated: true), lineWidth: 0.9)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(tool.detail)
    }
}

struct RuntimeSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: RuntimeMenuSummary
    let isSelected: Bool
    let language: WidgetLanguage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    RuntimeLogoView(scope: summary.scope, size: 24)
                    Text(summary.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(summary.status.localized(language))
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusTint.opacity(0.16))
                        )
                        .foregroundStyle(statusTint)
                }

                HStack(spacing: 10) {
                    if hasOfficialQuota {
                        quotaColumn(
                            title: language.text("5小时剩余", "5h left"),
                            value: summary.fiveHourRemainingPercent,
                            resetsAt: summary.fiveHourResetsAt
                        )
                        quotaColumn(
                            title: language.text("7日剩余", "7d left"),
                            value: summary.sevenDayRemainingPercent,
                            resetsAt: summary.sevenDayResetsAt
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("今日 token", "Today"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(runtimeFormatTokens(summary.todayTokens))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: hasOfficialQuota ? 82 : 160, alignment: .leading)
                }

                Text(localizedSourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? selectedFill : WidgetPalette.cardFill(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? selectedStroke : WidgetPalette.cardStroke(colorScheme), lineWidth: 0.9)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(language.text("打开 \(summary.displayName)", "Open \(summary.displayName)"))
    }

    private func quotaColumn(title: String, value: Double?, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(runtimeFormatPercent(value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    Capsule(style: .continuous)
                        .fill(statusTint.opacity(0.72))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, value ?? 0)) / 100))
                }
            }
            .frame(height: 4)
            Text(resetsAt.map { runtimeTimeOnly($0) } ?? "--")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 86, alignment: .leading)
    }

    private var statusTint: Color {
        switch summary.status {
        case .available:
            return WidgetPalette.statusSuccess
        case .localOnly:
            return WidgetPalette.statusInfo
        case .snapshotNeeded:
            return WidgetPalette.statusWarning
        case .stale:
            return WidgetPalette.statusInfo
        case .unavailable:
            return WidgetPalette.statusDanger
        }
    }

    private var hasOfficialQuota: Bool {
        summary.fiveHourRemainingPercent != nil || summary.sevenDayRemainingPercent != nil
    }

    private var selectedFill: Color {
        WidgetPalette.brandPrimary.opacity(colorScheme == .dark ? 0.16 : 0.09)
    }

    private var selectedStroke: Color {
        WidgetPalette.brandPrimary.opacity(colorScheme == .dark ? 0.34 : 0.26)
    }

    private var localizedSourceLabel: String {
        let label = summary.sourceLabel
        if language.isChinese {
            if label.contains("Codex app-server") {
                return "官方额度 + 本机统计"
            }
            if label.contains("OAuth usage") {
                return "官方 OAuth Usage + 本机统计"
            }
            if label.contains("OAuth cache") {
                return "OAuth 缓存 + 本机统计"
            }
            if label.contains("Relay/API key") {
                return "中转/API Key 本机统计"
            }
            if label.contains("statusLine") {
                return summary.fiveHourRemainingPercent == nil ? "本机统计；官方 Usage 暂不可用" : "active snapshot + 本机统计"
            }
            if label.contains("unavailable") {
                return "本机统计；官方 Usage 暂不可用"
            }
            return label
        }
        if label.contains("Codex app-server") {
            return "Official quota + local records"
        }
        if label.contains("statusLine") {
            return summary.fiveHourRemainingPercent == nil ? "Local records; official usage unavailable" : "Active snapshot + local records"
        }
        return label
    }
}

struct RuntimeLogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    let scope: RuntimeScope
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RuntimeLogo.image(for: scope) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
                    .background(WidgetPalette.controlFill(colorScheme))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous)
                .strokeBorder(WidgetPalette.cardStroke(colorScheme), lineWidth: 0.7)
        )
        .accessibilityHidden(true)
    }

    private var fallbackSystemName: String {
        switch scope {
        case .codex:
            return "terminal"
        case .claudeCode:
            return "curlybraces"
        }
    }
}

private enum RuntimeLogo {
    static func image(for scope: RuntimeScope) -> NSImage? {
        let name: String
        switch scope {
        case .codex:
            name = "codex-color"
        case .claudeCode:
            name = "claudecode-color"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private func runtimeFormatTokens(_ value: Int64?) -> String {
    guard let value else { return "--" }
    let absValue = abs(Double(value))
    if absValue >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if absValue >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

private func runtimeFormatPercent(_ value: Double?) -> String {
    guard let value else { return "--" }
    if value > 0, value < 1 {
        return "<1%"
    }
    return "\(Int(value.rounded()))%"
}

private func runtimeTimeOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
