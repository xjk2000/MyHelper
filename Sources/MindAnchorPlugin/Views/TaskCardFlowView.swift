import SwiftUI

struct TaskCardFlowView: View {
    let tasks: [TaskItem]
    let onComplete: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var cardScale: CGFloat = 1
    @State private var isCompleting = false

    private var currentTask: TaskItem? {
        tasks.first { $0.status != .done }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)

            if let currentTask {
                TaskHeroCard(
                    task: currentTask,
                    onComplete: { complete(currentTask) },
                    onDelete: { onDelete(currentTask) }
                )
                .id(currentTask.id)
                .offset(x: cardOffset)
                .opacity(cardOpacity)
                .scaleEffect(cardScale)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            // 右滑时给卡片橡皮筋阻尼，避免线性拖动带来的机械感。
                            let translation = max(value.translation.width, -26)
                            cardOffset = rubberBand(translation)
                            cardScale = 1 - min(abs(translation) / 1800, 0.035)
                        }
                        .onEnded { value in
                            if value.translation.width > 90 {
                                complete(currentTask)
                            } else {
                                withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.58, blendDuration: 0.08)) {
                                    cardOffset = 0
                                    cardScale = 1
                                }
                            }
                        }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.90).combined(with: .offset(x: -18)).combined(with: .opacity),
                    removal: .offset(x: 120).combined(with: .opacity)
                ))
                .contextMenu {
                    Button("完成") {
                        complete(currentTask)
                    }
                    Button("删除", role: .destructive) {
                        onDelete(currentTask)
                    }
                }
            } else {
                EmptyCardState()
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(minHeight: 208)
        .animation(.spring(response: 0.48, dampingFraction: 0.70, blendDuration: 0.10), value: currentTask?.id)
    }

    private func complete(_ task: TaskItem) {
        guard !isCompleting else { return }
        isCompleting = true

        withAnimation(.spring(response: 0.34, dampingFraction: 0.72, blendDuration: 0.08)) {
            cardOffset = 150
            cardOpacity = 0
            cardScale = 0.96
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            onComplete(task)
            cardOffset = -24
            cardOpacity = 0
            cardScale = 0.92

            withAnimation(.spring(response: 0.58, dampingFraction: 0.58, blendDuration: 0.12)) {
                cardOffset = 0
                cardOpacity = 1
                cardScale = 1
            }
            isCompleting = false
        }
    }

    private func rubberBand(_ value: CGFloat) -> CGFloat {
        let sign: CGFloat = value >= 0 ? 1 : -1
        let magnitude = abs(value)
        return sign * (1 - (1 / ((magnitude * 0.018) + 1))) * 92
    }
}

private struct TaskHeroCard: View {
    let task: TaskItem
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.sourceChannel.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))

                    Text(task.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 12)

                Button(action: onComplete) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.26), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("完成任务")
            }

            Spacer(minLength: 2)

            HStack(alignment: .center, spacing: 12) {
                DeadlineRing(task: task)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(deadlineTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.90))
                    Text(task.assignee.map { "相关人 \($0)" } ?? task.parseState.displayName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("删除任务")
            }

            TimelineBar(task: task)
                .frame(height: 5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .leading)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.31, green: 0.42, blue: 0.80).opacity(0.28), radius: 18, x: 0, y: 12)
        .padding(12)
    }

    private var deadlineTitle: String {
        guard let deadline = task.deadline else {
            return "未设置截止时间"
        }

        if deadline < Date() {
            return "已逾期 \(DisplayFormatters.deadline.string(from: deadline))"
        }

        return DisplayFormatters.deadline.string(from: deadline)
    }

    private var cardGradient: LinearGradient {
        let warm = Color(red: 0.98, green: 0.56, blue: 0.48)
        let cool = Color(red: 0.33, green: 0.62, blue: 0.96)
        let violet = Color(red: 0.72, green: 0.57, blue: 0.96)

        switch task.urgency {
        case .overdue:
            return LinearGradient(colors: [warm, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .soon:
            return LinearGradient(colors: [Color(red: 0.55, green: 0.68, blue: 0.98), violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .normal:
            return LinearGradient(colors: [cool, violet.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct TimelineBar: View {
    let task: TaskItem

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))

                Capsule()
                    .fill(timelineGradient)
                    .frame(width: max(8, proxy.size.width * progress))
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: progress)
            }
        }
    }

    private var progress: CGFloat {
        guard let deadline = task.deadline else {
            return 0.18
        }

        let total = max(deadline.timeIntervalSince(task.createdAt), 60)
        let elapsed = Date().timeIntervalSince(task.createdAt)
        return min(max(elapsed / total, 0), 1)
    }

    private var timelineGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.65, green: 0.92, blue: 0.98),
                task.urgency == .overdue ? Color(red: 1.00, green: 0.58, blue: 0.50) : Color(red: 0.92, green: 0.78, blue: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct DeadlineRing: View {
    let task: TaskItem

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 4)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: ringProgress)

            Image(systemName: task.deadline == nil ? "sparkle" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    private var ringProgress: CGFloat {
        guard let deadline = task.deadline else {
            return 0.32
        }
        let total = max(deadline.timeIntervalSince(task.createdAt), 60)
        let remaining = max(deadline.timeIntervalSinceNow, 0)
        return min(max(remaining / total, 0), 1)
    }

    private var ringColor: Color {
        switch task.urgency {
        case .normal: Color(red: 0.78, green: 0.96, blue: 1.00)
        case .soon: Color(red: 0.98, green: 0.88, blue: 0.58)
        case .overdue: Color(red: 1.00, green: 0.58, blue: 0.50)
        }
    }
}

private struct EmptyCardState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text("没有待处理任务")
                .font(.headline)
            Text("新的捕获会在这里以卡片出现")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
