import Foundation
import SwiftData
import UserNotifications

struct NotificationActionHandler {
    @MainActor
    func handle(actionIdentifier: String, taskIdString: String) async {
        guard let taskId = UUID(uuidString: taskIdString) else {
            AppLog.notification.error("notification_action_ignored reason=invalid_task_id taskId=\(taskIdString, privacy: .public) action=\(actionIdentifier, privacy: .public)")
            return
        }

        guard let modelContainer = AppRuntime.shared.modelContainer else {
            AppLog.notification.error("notification_action_ignored reason=model_container_missing taskId=\(taskId.uuidString, privacy: .public) action=\(actionIdentifier, privacy: .public)")
            return
        }

        // 通知动作会直接影响当前窗口中的 @Query 结果；使用 mainContext 能避免后台 context 保存后 UI 不及时刷新的问题。
        let modelContext = modelContainer.mainContext
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == taskId
            }
        )

        do {
            guard let task = try modelContext.fetch(descriptor).first else {
                AppLog.notification.error("notification_action_ignored reason=task_not_found taskId=\(taskId.uuidString, privacy: .public) action=\(actionIdentifier, privacy: .public)")
                return
            }

            switch actionIdentifier {
            case NotificationAction.markDone.rawValue:
                task.status = .done
                task.nextReminderAt = nil
                try modelContext.save()
                TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "notification_mark_done")
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskId.uuidString])
                AppLog.notification.info("notification_action_completed taskId=\(taskId.uuidString, privacy: .public)")

            case NotificationAction.snooze5Minutes.rawValue:
                try await snooze(task: task, modelContext: modelContext, minutes: 5)

            case NotificationAction.snooze1Hour.rawValue:
                try await snooze(task: task, modelContext: modelContext, minutes: 60)

            default:
                AppLog.notification.info("notification_action_noop taskId=\(taskId.uuidString, privacy: .public) action=\(actionIdentifier, privacy: .public)")
            }
        } catch {
            AppLog.notification.error("notification_action_failed taskId=\(taskId.uuidString, privacy: .public) action=\(actionIdentifier, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    private func snooze(task: TaskItem, modelContext: ModelContext, minutes: Int) async throws {
        let nextFireAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        task.nextReminderAt = nextFireAt
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "notification_snooze")
        try await scheduleSnoozedNotification(task: task, fireAt: nextFireAt)
        AppLog.notification.info("notification_action_snoozed taskId=\(task.id.uuidString, privacy: .public) minutes=\(minutes, privacy: .public) fireAt=\(nextFireAt.ISO8601Format(), privacy: .public)")
    }

    private func scheduleSnoozedNotification(task: TaskItem, fireAt: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.assignee.map { "相关人：\($0)" } ?? "稍后提醒"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)
    }
}
