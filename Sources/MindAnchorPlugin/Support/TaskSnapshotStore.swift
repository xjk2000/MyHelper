import Foundation
import SwiftData

enum TaskSnapshotStore {
    static let fileName = "tasks.json"

    static func importIfNeeded(modelContext: ModelContext) {
        do {
            let url = try snapshotURL()
            importIfNeeded(modelContext: modelContext, from: url, reason: "local_snapshot")
        } catch {
            AppLog.persistence.error("task_snapshot_import_failed error=\(String(describing: error), privacy: .public)")
        }
    }

    static func importIfNeeded(
        modelContext: ModelContext,
        from url: URL,
        reason: String,
        pathRewriter: (String?) -> String? = { $0 }
    ) {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<TaskItem>())
            guard existing.isEmpty else {
                AppLog.persistence.info("task_snapshot_import_skipped reason=target_not_empty source=\(reason, privacy: .public) existingCount=\(existing.count, privacy: .public)")
                return
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                AppLog.persistence.info("task_snapshot_import_skipped reason=file_missing source=\(reason, privacy: .public) path=\(url.path, privacy: .public)")
                return
            }

            let data = try Data(contentsOf: url)
            let payload = try decoder.decode(TaskSnapshotPayload.self, from: data)
            for task in payload.tasks {
                modelContext.insert(task.model(pathRewriter: pathRewriter))
            }

            try modelContext.save()
            AppLog.persistence.info("task_snapshot_import_completed source=\(reason, privacy: .public) importedCount=\(payload.tasks.count, privacy: .public) path=\(url.path, privacy: .public)")
        } catch {
            AppLog.persistence.error("task_snapshot_import_failed source=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    static func exportAll(modelContext: ModelContext, reason: String) {
        do {
            let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
            let payload = TaskSnapshotPayload(
                version: 1,
                exportedAt: Date(),
                tasks: tasks.map(TaskSnapshot.init)
            )
            let data = try encoder.encode(payload)
            let url = try snapshotURL()
            try data.write(to: url, options: .atomic)
            AppLog.persistence.info("task_snapshot_exported reason=\(reason, privacy: .public) taskCount=\(tasks.count, privacy: .public) path=\(url.path, privacy: .public)")
        } catch {
            // JSON 是可读镜像，不应该因为镜像写入失败让主 SQLite 保存回滚。
            AppLog.persistence.error("task_snapshot_export_failed reason=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    static func snapshotURL() throws -> URL {
        let directory = LocalTaskStore.projectRootURL().appendingPathComponent(LocalTaskStore.dataDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct TaskSnapshotPayload: Codable {
    let version: Int
    let exportedAt: Date
    let tasks: [TaskSnapshot]
}

private struct TaskSnapshot: Codable {
    let id: UUID
    let title: String
    let originalText: String
    let sourceChannelRawValue: String
    let assignee: String?
    let deadline: Date?
    let statusRawValue: String
    let parseStateRawValue: String
    let confidence: Double?
    let needsReview: Bool
    let isImportant: Bool?
    let isArchived: Bool?
    let audioFilePath: String?
    let screenshotFilePath: String?
    let transcriptText: String?
    let reminderOffsetMinutes: Int?
    let nextReminderAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let parsedAt: Date?
    let parseBaseDate: Date

    init(_ task: TaskItem) {
        self.id = task.id
        self.title = task.title
        self.originalText = task.originalText
        self.sourceChannelRawValue = task.sourceChannelRawValue
        self.assignee = task.assignee
        self.deadline = task.deadline
        self.statusRawValue = task.statusRawValue
        self.parseStateRawValue = task.parseStateRawValue
        self.confidence = task.confidence
        self.needsReview = task.needsReview
        self.isImportant = task.isImportant
        self.isArchived = task.isArchived
        self.audioFilePath = task.audioFilePath
        self.screenshotFilePath = task.screenshotFilePath
        self.transcriptText = task.transcriptText
        self.reminderOffsetMinutes = task.reminderOffsetMinutes
        self.nextReminderAt = task.nextReminderAt
        self.createdAt = task.createdAt
        self.updatedAt = task.updatedAt
        self.parsedAt = task.parsedAt
        self.parseBaseDate = task.parseBaseDate
    }

    var model: TaskItem {
        model(pathRewriter: { $0 })
    }

    func model(pathRewriter: (String?) -> String?) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            originalText: originalText,
            sourceChannel: SourceChannel(rawValue: sourceChannelRawValue) ?? .unknown,
            assignee: assignee,
            deadline: deadline,
            status: TaskStatus(rawValue: statusRawValue) ?? .todo,
            parseState: ParseState(rawValue: parseStateRawValue) ?? .failed,
            confidence: confidence,
            needsReview: needsReview,
            isImportant: isImportant ?? false,
            isArchived: isArchived ?? false,
            audioFilePath: pathRewriter(audioFilePath),
            screenshotFilePath: pathRewriter(screenshotFilePath),
            transcriptText: transcriptText,
            reminderOffsetMinutes: reminderOffsetMinutes,
            nextReminderAt: nextReminderAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            parsedAt: parsedAt,
            parseBaseDate: parseBaseDate
        )
    }
}
