import AppKit
import SwiftUI

struct CodexLocalProbePanel: View {
    let language: WidgetLanguage

    @State private var snapshot: CodexLocalProbeSnapshot? = CodexLocalProbeService.loadLastSnapshot()
    @State private var isRunning = false

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let snapshot {
                    content(snapshot)
                } else {
                    emptyState
                }

                sourceRow
            }
        }
        .frame(height: 190)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetPalette.brandSecondary)
                .frame(width: 18, height: 18)
            Text(language.text("Codex 本机探针", "Codex Local Probe"))
                .font(.system(size: 12, weight: .semibold))

            if let snapshot {
                Text(statusTitle(snapshot.status))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor(snapshot.status))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusColor(snapshot.status).opacity(0.12))
                    )
            }

            Spacer(minLength: 8)

            if let ranAt = snapshot?.ranAt {
                Text(localProbeDateText(ranAt, language: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                Task { await runProbe() }
            } label: {
                Label(
                    isRunning ? language.text("检测中", "Running") : language.text("检测一次", "Run"),
                    systemImage: isRunning ? "hourglass" : "play.fill"
                )
                .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRunning)
            .help(language.text("调用本机 codex exec 运行小型探针，会消耗少量额度", "Run a small probe through local codex exec"))
        }
        .frame(height: 24)
    }

    private func content(_ snapshot: CodexLocalProbeSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("本机分", "Local score"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(scoreText(snapshot.score))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor(snapshot.status))
                    .monospacedDigit()
                    .lineLimit(1)
                ProgressView(value: min(max(snapshot.score, 0), 100), total: 100)
                    .tint(statusColor(snapshot.status))
                Text("\(snapshot.passedTasks)/\(snapshot.totalTasks) · \(durationText(snapshot.durationSeconds))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 118, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("探针结果", "Probe tasks"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(snapshot.taskResults) { result in
                        probeTaskMetric(result)
                    }
                }

                if let errorMessage = snapshot.errorMessage, !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WidgetPalette.statusWarning)
                        .lineLimit(1)
                        .help(errorMessage)
                } else {
                    Text(language.text(
                        "结果来自本机当前 Codex 配置，不代表官方或公开雷达分数。",
                        "Uses your current local Codex config; not an official or public radar score."
                    ))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 105, maxHeight: 105, alignment: .topLeading)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("还没有本机探针结果", "No local probe result yet"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(language.text("点击“检测一次”后，会通过本机 codex exec 跑 4 个小型探针。", "Click Run to execute four small probes through local codex exec."))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 105, maxHeight: 105)
    }

    private var sourceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "book")
            Text(language.text("题型参考 HumanEval、MBPP、IFEval、GSM8K；内置题不是原题。", "Task types reference HumanEval, MBPP, IFEval, and GSM8K; prompts are not copied."))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 6)
            ForEach(CodexLocalProbeService.benchmarkSources.prefix(4)) { source in
                Button(source.id) {
                    if let url = URL(string: source.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .help(source.title)
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
    }

    private func probeTaskMetric(_ result: CodexLocalProbeTaskResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(result.passed ? WidgetPalette.statusSuccess : WidgetPalette.statusWarning)
                    .frame(width: 6, height: 6)
                Text(result.category)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(scoreText(result.score))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(result.passed ? WidgetPalette.statusSuccess : WidgetPalette.statusWarning)
                .monospacedDigit()
            Text(result.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .help(result.summary)
    }

    @MainActor
    private func runProbe() async {
        guard !isRunning else { return }
        isRunning = true
        snapshot = await CodexLocalProbeService().run()
        isRunning = false
    }

    private func statusTitle(_ status: CodexLocalProbeStatus) -> String {
        switch status {
        case .healthy:
            return language.text("本机正常", "Healthy")
        case .unstable:
            return language.text("表现波动", "Unstable")
        case .degraded:
            return language.text("疑似降智", "Degraded")
        case .failed:
            return language.text("检测失败", "Failed")
        }
    }

    private func statusColor(_ status: CodexLocalProbeStatus) -> Color {
        switch status {
        case .healthy:
            return WidgetPalette.statusSuccess
        case .unstable:
            return WidgetPalette.statusWarning
        case .degraded, .failed:
            return WidgetPalette.statusDanger
        }
    }

    private func scoreText(_ score: Double) -> String {
        score.rounded() == score ? String(Int(score)) : String(format: "%.1f", score)
    }

    private func durationText(_ seconds: Double) -> String {
        if seconds <= 0 { return "--" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%.1fmin", seconds / 60)
    }
}

private func localProbeDateText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.isChinese
        ? Locale(identifier: "zh_CN")
        : Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = language.isChinese ? "M月d日 HH:mm" : "MMM d HH:mm"
    return formatter.string(from: date)
}
