import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalText: String
    var sourceChannelRawValue: String
    var assignee: String?
    var deadline: Date?
    var statusRawValue: String
    var parseStateRawValue: String
    var confidence: Double?
    var needsReview: Bool
    var isImportantRaw: Bool?
    var isArchivedRaw: Bool?

    var audioFilePath: String?
    var screenshotFilePath: String?
    var transcriptText: String?

    var reminderOffsetMinutes: Int?
    var nextReminderAt: Date?

    var createdAt: Date
    var updatedAt: Date
    var parsedAt: Date?
    var parseBaseDate: Date

    init(
        id: UUID = UUID(),
        title: String,
        originalText: String = "",
        sourceChannel: SourceChannel = .unknown,
        assignee: String? = nil,
        deadline: Date? = nil,
        status: TaskStatus = .todo,
        parseState: ParseState = .pending,
        confidence: Double? = nil,
        needsReview: Bool = true,
        isImportant: Bool = false,
        isArchived: Bool = false,
        audioFilePath: String? = nil,
        screenshotFilePath: String? = nil,
        transcriptText: String? = nil,
        reminderOffsetMinutes: Int? = 60,
        nextReminderAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        parsedAt: Date? = nil,
        parseBaseDate: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.originalText = originalText
        self.sourceChannelRawValue = sourceChannel.rawValue
        self.assignee = assignee
        self.deadline = deadline
        self.statusRawValue = status.rawValue
        self.parseStateRawValue = parseState.rawValue
        self.confidence = confidence
        self.needsReview = needsReview
        self.isImportantRaw = isImportant
        self.isArchivedRaw = isArchived
        self.audioFilePath = audioFilePath
        self.screenshotFilePath = screenshotFilePath
        self.transcriptText = transcriptText
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.nextReminderAt = nextReminderAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parsedAt = parsedAt
        self.parseBaseDate = parseBaseDate
    }
}

extension TaskItem {
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .todo }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var parseState: ParseState {
        get { ParseState(rawValue: parseStateRawValue) ?? .failed }
        set {
            parseStateRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var sourceChannel: SourceChannel {
        get { SourceChannel(rawValue: sourceChannelRawValue) ?? .unknown }
        set {
            sourceChannelRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var isImportant: Bool {
        get { isImportantRaw ?? false }
        set {
            isImportantRaw = newValue
            updatedAt = Date()
        }
    }

    var isArchived: Bool {
        get { isArchivedRaw ?? false }
        set {
            isArchivedRaw = newValue
            updatedAt = Date()
        }
    }

    var urgency: TaskUrgency {
        guard status != .done, let deadline else {
            return .normal
        }

        let remaining = deadline.timeIntervalSinceNow
        if remaining < 0 {
            return .overdue
        }

        // MVP 将 24 小时内到期视为临近，后续可按用户偏好调整阈值。
        if remaining <= 24 * 60 * 60 {
            return .soon
        }

        return .normal
    }
}
