import SwiftData
import SwiftUI

struct SprintMenuBoardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TaskItem.updatedAt, order: .reverse)
    private var tasks: [TaskItem]

    @State private var droppedTaskId: UUID?

    private var sprintTasks: [TaskItem] {
        let sprintRange = Self.currentWeekInterval()
        return tasks
            .filter { task in
                !task.isArchived
                    && (task.status != .done
                        || sprintRange.contains(task.updatedAt)
                        || task.deadline.map(sprintRange.contains) == true)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("当前 Sprint")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(sprintTasks.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.weekTitle())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(TaskStatus.allCases) { status in
                    SprintMenuColumn(
                        status: status,
                        tasks: tasks(for: status),
                        droppedTaskId: droppedTaskId,
                        onDropTask: { taskId in
                            moveTask(taskId: taskId, to: status)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        sprintTasks.filter { $0.status == status }
    }

    private func moveTask(taskId: UUID, to status: TaskStatus) {
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            AppLog.persistence.error("sprint_drag_status_update_skipped taskId=\(taskId.uuidString, privacy: .public) reason=task_not_found surface=menu_bar")
            return
        }
        guard task.status != status else { return }

        do {
            try TaskRepository(modelContext: modelContext).updateStatus(task, status: status)
            droppedTaskId = task.id
            AppLog.persistence.info("sprint_drag_status_updated taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public) surface=menu_bar")
        } catch {
            AppLog.persistence.error("sprint_drag_status_update_failed taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public) surface=menu_bar error=\(String(describing: error), privacy: .public)")
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

    private static func weekTitle(referenceDate: Date = Date()) -> String {
        let interval = currentWeekInterval(referenceDate: referenceDate)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "M.d"
        return "\(formatter.string(from: interval.start)) - \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
    }
}

private struct SprintMenuColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let droppedTaskId: UUID?
    let onDropTask: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(status.menuBoardColor)
                    .frame(width: 7, height: 7)
                Text(status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(tasks.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: tasks.count > 3) {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { task in
                        SprintMenuTaskCard(
                            task: task,
                            isRecentlyDropped: droppedTaskId == task.id
                        )
                        .draggable(task.id.uuidString)
                    }

                    if tasks.isEmpty {
                        Text("拖到这里")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(5)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isTargeted ? status.menuBoardColor.opacity(0.10) : Color.primary.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isTargeted ? status.menuBoardColor.opacity(0.72) : Color.primary.opacity(0.08),
                        lineWidth: isTargeted ? 1.5 : 0.8
                    )
            }
            .dropDestination(for: String.self) { items, _ in
                guard let rawId = items.first, let taskId = UUID(uuidString: rawId) else {
                    AppLog.persistence.error("sprint_drag_drop_rejected status=\(status.rawValue, privacy: .public) reason=invalid_payload surface=menu_bar")
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
}

private struct SprintMenuTaskCard: View {
    let task: TaskItem
    let isRecentlyDropped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let deadline = task.deadline {
                Label(DisplayFormatters.deadline.string(from: deadline), systemImage: "clock")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(task.urgency.color)
                    .lineLimit(1)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isRecentlyDropped ? task.status.menuBoardColor.opacity(0.72) : Color.primary.opacity(0.08),
                    lineWidth: isRecentlyDropped ? 1.4 : 0.8
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private extension TaskStatus {
    var menuBoardColor: Color {
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
