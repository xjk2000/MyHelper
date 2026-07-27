import Foundation
import SwiftData

@MainActor
struct TaskRepository {
    let modelContext: ModelContext

    func addManualTask(title: String, deadline: Date? = nil) throws {
        let task = TaskItem(
            title: title,
            originalText: title,
            deadline: deadline,
            parseState: .parsed,
            needsReview: false
        )
        modelContext.insert(task)
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "manual_task_created")
        AppLog.persistence.info("manual_task_created taskId=\(task.id.uuidString, privacy: .public) deadline=\(deadline?.ISO8601Format() ?? "nil", privacy: .public)")
    }

    func updateStatus(_ task: TaskItem, status: TaskStatus) throws {
        task.status = status
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_status_updated")
        AppLog.persistence.info("task_status_updated taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public)")
    }

    func saveEdits(
        _ task: TaskItem,
        title: String,
        originalText: String,
        sourceChannel: SourceChannel,
        assignee: String?,
        deadline: Date?,
        status: TaskStatus,
        needsReview: Bool,
        isImportant: Bool,
        isArchived: Bool
    ) throws {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.originalText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        task.sourceChannel = sourceChannel
        task.assignee = assignee?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        task.deadline = deadline
        task.status = status
        task.needsReview = needsReview
        task.isImportant = isImportant
        task.isArchived = isArchived
        task.parseState = .parsed
        task.updatedAt = Date()

        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_edits_saved")
        AppLog.persistence.info("task_edits_saved taskId=\(task.id.uuidString, privacy: .public) status=\(status.rawValue, privacy: .public) sourceChannel=\(sourceChannel.rawValue, privacy: .public) hasDeadline=\((deadline != nil), privacy: .public) needsReview=\(needsReview, privacy: .public) isImportant=\(isImportant, privacy: .public) isArchived=\(isArchived, privacy: .public)")
    }

    func updateImportance(_ task: TaskItem, isImportant: Bool) throws {
        task.isImportant = isImportant
        task.updatedAt = Date()
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_importance_updated")
        AppLog.persistence.info("task_importance_updated taskId=\(task.id.uuidString, privacy: .public) isImportant=\(isImportant, privacy: .public)")
    }

    func updateArchiveState(_ task: TaskItem, isArchived: Bool) throws {
        task.isArchived = isArchived
        task.updatedAt = Date()
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_archive_updated")
        AppLog.persistence.info("task_archive_updated taskId=\(task.id.uuidString, privacy: .public) isArchived=\(isArchived, privacy: .public)")
    }

    func updateReviewState(_ task: TaskItem, isReviewed: Bool) throws {
        task.needsReview = !isReviewed
        task.updatedAt = Date()
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_review_state_updated")
        AppLog.persistence.info("task_review_state_updated taskId=\(task.id.uuidString, privacy: .public) isReviewed=\(isReviewed, privacy: .public)")
    }

    func delete(_ task: TaskItem, deleteAudioFile: Bool = false) throws {
        let taskId = task.id
        let audioFilePath = task.audioFilePath
        modelContext.delete(task)
        try modelContext.save()
        TaskSnapshotStore.exportAll(modelContext: modelContext, reason: "task_deleted")

        if deleteAudioFile {
            try deleteAudioFileIfNeeded(path: audioFilePath, taskId: taskId)
        }

        AppLog.persistence.info("task_deleted taskId=\(taskId.uuidString, privacy: .public) deleteAudioFile=\(deleteAudioFile, privacy: .public) hadAudio=\((audioFilePath != nil), privacy: .public)")
    }

    private func deleteAudioFileIfNeeded(path: String?, taskId: UUID) throws {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLog.persistence.info("task_audio_delete_skipped taskId=\(taskId.uuidString, privacy: .public) reason=no_audio_path")
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            AppLog.persistence.info("task_audio_delete_skipped taskId=\(taskId.uuidString, privacy: .public) reason=file_missing")
            return
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            AppLog.persistence.info("task_audio_deleted taskId=\(taskId.uuidString, privacy: .public) fileName=\(URL(fileURLWithPath: path).lastPathComponent, privacy: .public)")
        } catch {
            AppLog.persistence.error("task_audio_delete_failed taskId=\(taskId.uuidString, privacy: .public) fileName=\(URL(fileURLWithPath: path).lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw TaskRepositoryError.audioDeleteFailed(path: path, underlying: error)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum TaskRepositoryError: LocalizedError {
    case audioDeleteFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .audioDeleteFailed(path, underlying):
            return "任务已删除，但音频文件删除失败：\(URL(fileURLWithPath: path).lastPathComponent)。\(underlying.localizedDescription)"
        }
    }
}
