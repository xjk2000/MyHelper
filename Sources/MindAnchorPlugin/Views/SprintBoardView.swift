import SwiftData
import SwiftUI

struct SprintBoardView: View {
    @Environment(\.modelContext) private var modelContext

    let tasks: [TaskItem]

    @State private var droppedTaskId: UUID?

    private var sprintRange: DateInterval {
        Self.currentWeekInterval()
    }

    private var sprintTasks: [TaskItem] {
        tasks
            .filter { task in
                // 轻量 Sprint 规则：未完成任务始终进入当前 Sprint；已完成任务只保留本周完成/更新过的上下文。
                task.status != .done
                    || sprintRange.contains(task.updatedAt)
                    || task.deadline.map(sprintRange.contains) == true
            }
            .sorted { lhs, rhs in
                switch (lhs.deadline, rhs.deadline) {
                case let (left?, right?):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.createdAt > rhs.createdAt
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases) { status in
                    SprintStatusColumn(
                        status: status,
                        tasks: tasks(for: status),
                        droppedTaskId: droppedTaskId,
                        onDropTask: { taskId in
                            moveTask(taskId: taskId, to: status)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(22)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前 Sprint")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("\(DisplayFormatters.preciseDate.string(from: sprintRange.start)) - \(DisplayFormatters.preciseDate.string(from: sprintRange.end.addingTimeInterval(-1)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                SprintMetric(title: "全部", value: sprintTasks.count, color: .secondary)
                SprintMetric(title: "处理中", value: tasks(for: .doing).count, color: .blue)
                SprintMetric(title: "完成", value: tasks(for: .done).count, color: .green)
            }
        }
    }

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        sprintTasks.filter { $0.status == status }
    }

    private func moveTask(taskId: UUID, to status: TaskStatus) {
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            AppLog.persistence.error("sprint_drag_status_update_skipped taskId=\(taskId.uuidString, privacy: .public) reason=task_not_found")
            return
        }

        guard task.status != status else {
            AppLog.persistence.info("sprint_drag_status_update_skipped taskId=\(task.id.uuidString, privacy: .public) reason=status_unchanged status=\(status.rawValue, privacy: .public)")
            return
        }

        do {
            try TaskRepository(modelContext: modelContext).updateStatus(task, status: status)
            droppedTaskId = task.id
            AppLog.persistence.info("sprint_drag_status_updated taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public) surface=sprint_board")
        } catch {
            AppLog.persistence.error("sprint_drag_status_update_failed taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private static func currentWeekInterval(referenceDate: Date = Date()) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }
}

private struct SprintStatusColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let droppedTaskId: UUID?
    let onDropTask: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.boardColor)
                    .frame(width: 8, height: 8)
                Text(status.displayName)
                    .font(.headline)
                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        SprintTaskCard(task: task, isRecentlyDropped: droppedTaskId == task.id)
                            .draggable(task.id.uuidString)
                    }

                    if tasks.isEmpty {
                        emptyState
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .background(columnBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isTargeted ? status.boardColor.opacity(0.70) : Color.primary.opacity(0.07), lineWidth: isTargeted ? 2 : 1)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let rawId = items.first, let taskId = UUID(uuidString: rawId) else {
                    AppLog.persistence.error("sprint_drag_drop_rejected status=\(status.rawValue, privacy: .public) reason=invalid_payload")
                    return false
                }

                onDropTask(taskId)
                return true
            } isTargeted: { value in
                isTargeted = value
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var columnBackground: Color {
        isTargeted ? status.boardColor.opacity(0.08) : Color.primary.opacity(0.035)
    }

    private var emptyState: some View {
        Text("拖到这里")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

private struct SprintTaskCard: View {
    let task: TaskItem
    let isRecentlyDropped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Spacer(minLength: 4)
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                SprintChip(title: task.sourceChannel.displayName, color: .secondary)
                SprintChip(title: task.parseState.displayName, color: task.needsReview ? .orange : .green)
            }

            if let deadline = task.deadline {
                Label(DisplayFormatters.preciseDeadline.string(from: deadline), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(task.urgency.color)
                    .lineLimit(1)
            }

            if let assignee = task.assignee {
                Label(assignee, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isRecentlyDropped ? task.status.boardColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: isRecentlyDropped ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
        .scaleEffect(isRecentlyDropped ? 1.018 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.70), value: isRecentlyDropped)
    }
}

private struct SprintMetric: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(width: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct SprintChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private extension TaskStatus {
    var boardColor: Color {
        switch self {
        case .todo:
            return .blue
        case .doing:
            return .orange
        case .done:
            return .green
        }
    }
}
