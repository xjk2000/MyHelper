import Foundation
import UserNotifications

protocol NotificationScheduling: Sendable {
    func scheduleReminder(for task: TaskItem) async throws
    func markDone(taskId: UUID) async
    func snooze(taskId: UUID, minutes: Int) async throws
}

struct UserNotificationScheduler: NotificationScheduling {
    func scheduleReminder(for task: TaskItem) async throws {
        guard let deadline = task.deadline else {
            AppLog.notification.info("notification_skipped taskId=\(task.id.uuidString, privacy: .public) reason=no_deadline")
            return
        }

        let offset = task.reminderOffsetMinutes ?? 60
        let fireDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))

        guard fireDate > Date() else {
            AppLog.notification.info("notification_skipped taskId=\(task.id.uuidString, privacy: .public) reason=fire_date_in_past deadline=\(deadline.ISO8601Format(), privacy: .public)")
            return
        }

        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            AppLog.notification.error("notification_permission_denied taskId=\(task.id.uuidString, privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.assignee.map { "相关人：\($0)" } ?? "任务即将到期"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        try await center.add(request)
        AppLog.notification.info("notification_scheduled taskId=\(task.id.uuidString, privacy: .public) fireAt=\(fireDate.ISO8601Format(), privacy: .public) deadline=\(deadline.ISO8601Format(), privacy: .public)")
    }

    func markDone(taskId: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskId.uuidString])
        AppLog.notification.info("notification_mark_done_requested taskId=\(taskId.uuidString, privacy: .public)")
    }

    func snooze(taskId: UUID, minutes: Int) async throws {
        AppLog.notification.info("notification_snooze_requested taskId=\(taskId.uuidString, privacy: .public) minutes=\(minutes, privacy: .public)")
    }
}

enum NotificationCategory: String {
    case taskReminder = "TASK_REMINDER"
}

enum NotificationAction: String {
    case markDone = "MARK_DONE"
    case snooze5Minutes = "SNOOZE_5_MINUTES"
    case snooze1Hour = "SNOOZE_1_HOUR"
}
