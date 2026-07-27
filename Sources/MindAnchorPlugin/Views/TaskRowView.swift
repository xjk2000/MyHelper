import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isSelected ? Color.accentColor : task.urgency.color.opacity(0.75))
                .frame(width: 4)
                .padding(.vertical, 5)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(task.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if task.isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    if task.isArchived {
                        Image(systemName: "archivebox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.status.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    TaskRowBadge(task.sourceChannel.displayName, color: .secondary)
                    TaskRowBadge(task.parseState.displayName, color: .secondary)
                    if let assignee = task.assignee {
                        TaskRowBadge(assignee, color: .secondary)
                    }
                }

                if let deadline = task.deadline {
                    Label(DisplayFormatters.preciseDeadline.string(from: deadline), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if task.needsReview {
                    TaskRowBadge("解析待确认", color: .orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035)
    }
}

private struct TaskRowBadge: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

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
