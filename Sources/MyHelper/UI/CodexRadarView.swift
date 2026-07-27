import AppKit
import SwiftUI

struct ModelRadarPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let language: WidgetLanguage
    let runtimeScope: RuntimeScope

    @State private var snapshot: ModelRadarSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 9) {
                header

                Group {
                    if let snapshot {
                        radarContent(snapshot)
                    } else if isLoading {
                        loadingState
                    } else {
                        errorState
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)

                sourceFooter
            }
        }
        .frame(height: 224)
        .task {
            await loadRadar()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(runtimeScope == .codex ? WidgetPalette.statusInfo : WidgetPalette.statusWarning)
                .frame(width: 18, height: 18)
            Text(radarTitle)
                .font(.system(size: 12, weight: .semibold))

            if let snapshot {
                Text(statusTitle(snapshot.latest.status))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(snapshot.latest.status.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(snapshot.latest.status.tint.opacity(0.12))
                    )
            }

            Spacer(minLength: 8)

            if let updatedAt = snapshot?.updatedAt {
                Text(radarUpdatedAtText(updatedAt, language: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                Task { await loadRadar() }
            } label: {
                Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help(language.text("刷新降智雷达", "Refresh model IQ radar"))

            Button {
                NSWorkspace.shared.open(snapshot?.sourceURL ?? ModelRadarService.sourceURL(for: runtimeScope))
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(openRadarHelp)
        }
        .frame(height: 22)
    }

    private func radarContent(_ snapshot: ModelRadarSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            currentScore(snapshot.latest)
                .frame(width: 132, height: 150, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("\(shortModelLabel(snapshot.latest.label)) · \(language.text("近 7 次", "Last 7"))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                ModelRadarTrendChart(
                    readings: Array(snapshot.recentReadings.suffix(7)),
                    language: language
                )
            }
            .frame(width: 238, height: 150, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("本次模型对比", "Latest model comparison"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: snapshot.modelReadings.count > 9 ? 4 : 3
                    ),
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(snapshot.modelReadings, id: \.key) { reading in
                        ModelRadarMetric(reading: reading)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        }
    }

    private func currentScore(_ reading: ModelRadarReading) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(reading.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(radarScoreText(reading.score))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(reading.status.tint)
                .monospacedDigit()
                .lineLimit(1)

            ProgressView(value: min(max(reading.score, 0), 150), total: 150)
                .tint(reading.status.tint)

            HStack(spacing: 5) {
                Label("\(reading.passed)/\(reading.tasks)", systemImage: "checkmark.circle")
                if let wallTime = reading.wallTimeHuman, !wallTime.isEmpty {
                    Text("·")
                    Text(wallTime)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(radarRunDateText(reading.date, language: language))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text(loadingText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetPalette.statusWarning)
            Text(errorMessage ?? language.text("暂时无法读取降智雷达", "Model IQ radar is unavailable"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(language.text("重试", "Retry")) {
                Task { await loadRadar() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceFooter: some View {
        Button {
            NSWorkspace.shared.open(snapshot?.sourceURL ?? ModelRadarService.sourceURL(for: runtimeScope))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                Text(snapshot?.attribution ?? fallbackAttribution)
                Text("·")
                Text(language.text("社区测试，非官方指标", "Community test, not an official metric"))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text("查看数据来源", "View data source"))
    }

    @MainActor
    private func loadRadar() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            snapshot = try await ModelRadarService().load(for: runtimeScope)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func statusTitle(_ status: ModelRadarStatus) -> String {
        switch status {
        case .green:
            return language.text("状态良好", "Healthy")
        case .yellow:
            return language.text("表现波动", "Unstable")
        case .red:
            return language.text("疑似降智", "Degraded")
        case .unknown:
            return language.text("状态未知", "Unknown")
        }
    }

    private var radarTitle: String {
        switch runtimeScope {
        case .codex:
            return language.text("Codex 降智雷达", "Codex Model IQ Radar")
        case .claudeCode:
            return language.text("Claude Code 降智雷达", "Claude Code IQ Radar")
        }
    }

    private var loadingText: String {
        switch runtimeScope {
        case .codex:
            return language.text("正在读取 Codex 雷达公开摘要", "Loading Codex Radar public summary")
        case .claudeCode:
            return language.text("正在读取 Claude Code 雷达数据", "Loading Claude Code Radar data")
        }
    }

    private var fallbackAttribution: String {
        switch runtimeScope {
        case .codex:
            return "数据来自 Codex 雷达 codexradar.com"
        case .claudeCode:
            return "数据来自 Claude Code 雷达 claudecoderadar.com"
        }
    }

    private var openRadarHelp: String {
        switch runtimeScope {
        case .codex:
            return language.text("打开 Codex 雷达", "Open Codex Radar")
        case .claudeCode:
            return language.text("打开 Claude Code 雷达", "Open Claude Code Radar")
        }
    }
}

private struct ModelRadarTrendChart: View {
    let readings: [ModelRadarReading]
    let language: WidgetLanguage

    var body: some View {
        if readings.isEmpty {
            Text(language.text("暂无趋势数据", "No trend data"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    let points = chartPoints(in: geometry.size)

                    ZStack {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { index in
                                Rectangle()
                                    .fill(WidgetPalette.surfaceTrack)
                                    .frame(height: 1)
                                if index < 3 { Spacer() }
                            }
                        }

                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        .stroke(WidgetPalette.statusInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            Circle()
                                .fill(readings[index].status.tint)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                                .position(point)

                            Text(radarScoreText(readings[index].score))
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundStyle(readings[index].status.tint)
                                .monospacedDigit()
                                .position(x: point.x, y: max(7, point.y - 10))
                        }
                    }
                }
                .frame(height: 100)

                HStack(spacing: 0) {
                    ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                        Text(radarRunDateText(reading.date, language: language, compact: true))
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 12
        let usableWidth = max(0, size.width - horizontalInset * 2)
        let usableHeight = max(0, size.height - verticalInset * 2)

        return readings.enumerated().map { index, reading in
            let xRatio = readings.count > 1
                ? CGFloat(index) / CGFloat(readings.count - 1)
                : 0.5
            let scoreRatio = CGFloat(min(max(reading.score, 0), 150) / 150)
            return CGPoint(
                x: horizontalInset + usableWidth * xRatio,
                y: verticalInset + usableHeight * (1 - scoreRatio)
            )
        }
    }
}

private struct ModelRadarMetric: View {
    let reading: ModelRadarReading

    var body: some View {
        HStack(spacing: 5) {
            Capsule(style: .continuous)
                .fill(reading.status.tint)
                .frame(width: 3, height: 25)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortLabel)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(radarScoreText(reading.score))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(reading.status.tint)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private var shortLabel: String {
        shortModelLabel(reading.label)
    }
}

private extension ModelRadarStatus {
    var tint: Color {
        switch self {
        case .green:
            return WidgetPalette.statusSuccess
        case .yellow:
            return WidgetPalette.statusWarning
        case .red:
            return WidgetPalette.statusDanger
        case .unknown:
            return .secondary
        }
    }
}

private func radarScoreText(_ score: Double) -> String {
    score.rounded() == score ? String(Int(score)) : String(format: "%.1f", score)
}

private func shortModelLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "GPT-5.6 ", with: "")
        .replacingOccurrences(of: "GPT 5.6 ", with: "")
}

private func radarRunDateText(
    _ rawValue: String,
    language: WidgetLanguage,
    compact: Bool = false
) -> String {
    if let date = radarRunDate(from: rawValue) {
        let formatter = DateFormatter()
        formatter.locale = language.isChinese
            ? Locale(identifier: "zh_CN")
            : Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = compact ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    let parts = rawValue.split(separator: "-").map(String.init)
    guard parts.count >= 3 else { return rawValue }

    let month = Int(parts[1]) ?? 0
    let day = Int(parts[2]) ?? 0
    guard month > 0, day > 0 else { return rawValue }

    let period = parts.count > 3 ? parts[3].lowercased() : ""
    if compact {
        let suffix: String
        switch period {
        case "am": suffix = language.text("早", "A")
        case "pm": suffix = language.text("午", "P")
        case "n": suffix = language.text("夜", "N")
        default: suffix = ""
        }
        return "\(month)/\(day)\(suffix)"
    }

    let suffix: String
    switch period {
    case "am": suffix = language.text("上午", "AM")
    case "pm": suffix = language.text("下午", "PM")
    case "n": suffix = language.text("夜间", "Night")
    default: suffix = ""
    }
    return ["\(month)/\(day)", suffix].filter { !$0.isEmpty }.joined(separator: " ")
}

private func radarRunDate(from rawValue: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: rawValue) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: rawValue)
}

private func radarUpdatedAtText(_ date: Date, language: WidgetLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.isChinese
        ? Locale(identifier: "zh_CN")
        : Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = language.isChinese ? "M月d日 HH:mm 更新" : "MMM d HH:mm"
    return formatter.string(from: date)
}
