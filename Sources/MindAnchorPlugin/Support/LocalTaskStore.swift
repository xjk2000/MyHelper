import Foundation
import SwiftData

enum LocalTaskStore {
    static let dataDirectoryName = "Data"
    static let storeFileName = "MindAnchor.store"

    static func makeContainer(schema: Schema) throws -> ModelContainer {
        let url = try storeURL()
        let configuration = ModelConfiguration(schema: schema, url: url)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            AppLog.persistence.info("task_store_opened path=\(url.path, privacy: .public)")
            return container
        } catch {
            AppLog.persistence.error("task_store_open_failed path=\(url.path, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return try rebuildContainerFromSnapshot(schema: schema, storeURL: url, originalError: error)
        }
    }

    static func migrateLegacyDefaultStoreIfNeeded(to targetContainer: ModelContainer, schema: Schema) {
        do {
            let targetContext = ModelContext(targetContainer)
            migrateLegacyProjectDataIfNeeded(to: targetContext)
            TaskSnapshotStore.importIfNeeded(modelContext: targetContext)

            let existingTasks = try targetContext.fetch(FetchDescriptor<TaskItem>())
            guard existingTasks.isEmpty else {
                AppLog.persistence.info("task_store_legacy_migration_skipped reason=target_not_empty existingCount=\(existingTasks.count, privacy: .public)")
                return
            }

            let legacyConfiguration = ModelConfiguration(schema: schema)
            let legacyContainer = try ModelContainer(for: schema, configurations: [legacyConfiguration])
            let legacyContext = ModelContext(legacyContainer)
            let legacyTasks = try legacyContext.fetch(FetchDescriptor<TaskItem>())
            guard !legacyTasks.isEmpty else {
                AppLog.persistence.info("task_store_legacy_migration_skipped reason=legacy_empty")
                return
            }

            for task in legacyTasks {
                targetContext.insert(copy(task))
            }

            try targetContext.save()
            TaskSnapshotStore.exportAll(modelContext: targetContext, reason: "legacy_migration")
            AppLog.persistence.info("task_store_legacy_migration_completed importedCount=\(legacyTasks.count, privacy: .public)")
        } catch {
            // 迁移失败不能阻断应用启动；明确记录原因，用户仍可用项目目录的新持久化库继续工作。
            AppLog.persistence.error("task_store_legacy_migration_failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private static func migrateLegacyProjectDataIfNeeded(to targetContext: ModelContext) {
        do {
            let existingTasks = try targetContext.fetch(FetchDescriptor<TaskItem>())
            guard existingTasks.isEmpty else {
                AppLog.persistence.info("task_store_legacy_project_migration_skipped reason=target_not_empty existingCount=\(existingTasks.count, privacy: .public)")
                return
            }

            let snapshotURL = legacyProjectDataURL.appendingPathComponent(TaskSnapshotStore.fileName)
            guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
                AppLog.persistence.info("task_store_legacy_project_migration_skipped reason=snapshot_missing path=\(snapshotURL.path, privacy: .public)")
                return
            }

            try copyLegacyAttachmentsIfNeeded()
            TaskSnapshotStore.importIfNeeded(
                modelContext: targetContext,
                from: snapshotURL,
                reason: "legacy_project_snapshot",
                pathRewriter: rewriteLegacyAttachmentPath
            )
            TaskSnapshotStore.exportAll(modelContext: targetContext, reason: "legacy_project_migration")
        } catch {
            // 旧项目数据迁移失败不能阻断 MyHelper 启动；保留日志，用户仍可继续使用新目录。
            AppLog.persistence.error("task_store_legacy_project_migration_failed error=\(String(describing: error), privacy: .public)")
        }
    }

    static func storeURL() throws -> URL {
        let directory = projectRootURL().appendingPathComponent(dataDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(storeFileName)
    }

    static func projectRootURL() -> URL {
        if let configuredRoot = ProcessInfo.processInfo.environment["MINDANCHOR_PROJECT_ROOT"], !configuredRoot.isEmpty {
            return URL(fileURLWithPath: configuredRoot, isDirectory: true)
        }

        let bundleURL = Bundle.main.bundleURL
        let bundleParent = bundleURL.deletingLastPathComponent()
        if bundleURL.pathExtension == "app", bundleParent.lastPathComponent == "dist" {
            return bundleParent.deletingLastPathComponent()
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("Package.swift").path) {
            return currentDirectory
        }

        // 作为 MyHelper 内置插件运行时，默认数据不再写回 MindAnchor 源码目录。
        return applicationSupportRootURL()
    }

    static func applicationSupportRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MyHelper", isDirectory: true)
            .appendingPathComponent("MindAnchor", isDirectory: true)
    }

    private static let legacyProjectRootURL = URL(fileURLWithPath: "/Volumes/ORICO/Projects/MindAnchor", isDirectory: true)

    private static var legacyProjectDataURL: URL {
        legacyProjectRootURL.appendingPathComponent(dataDirectoryName, isDirectory: true)
    }

    private static var legacyRecordingsDirectoryURL: URL {
        legacyProjectDataURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    private static var legacyScreenshotsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MindAnchor", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static var currentRecordingsDirectoryURL: URL {
        applicationSupportRootURL()
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private static var currentScreenshotsDirectoryURL: URL {
        applicationSupportRootURL()
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static func copyLegacyAttachmentsIfNeeded() throws {
        try copyDirectoryContentsIfPresent(from: legacyRecordingsDirectoryURL, to: currentRecordingsDirectoryURL)
        try copyDirectoryContentsIfPresent(from: legacyScreenshotsDirectoryURL, to: currentScreenshotsDirectoryURL)
    }

    private static func copyDirectoryContentsIfPresent(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            AppLog.persistence.info("legacy_attachment_copy_skipped reason=source_missing source=\(source.path, privacy: .public)")
            return
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var copiedCount = 0
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try FileManager.default.copyItem(at: file, to: target)
            copiedCount += 1
        }
        AppLog.persistence.info("legacy_attachment_copy_completed source=\(source.path, privacy: .public) destination=\(destination.path, privacy: .public) copiedCount=\(copiedCount, privacy: .public)")
    }

    private static func rewriteLegacyAttachmentPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return path }

        if let rewritten = rewritePath(
            path,
            from: legacyRecordingsDirectoryURL,
            to: currentRecordingsDirectoryURL
        ) {
            return rewritten
        }

        if let rewritten = rewritePath(
            path,
            from: legacyScreenshotsDirectoryURL,
            to: currentScreenshotsDirectoryURL
        ) {
            return rewritten
        }

        return path
    }

    private static func rewritePath(_ path: String, from sourceDirectory: URL, to destinationDirectory: URL) -> String? {
        let sourcePrefix = sourceDirectory.path.hasSuffix("/") ? sourceDirectory.path : sourceDirectory.path + "/"
        guard path.hasPrefix(sourcePrefix) else { return nil }
        let relativePath = String(path.dropFirst(sourcePrefix.count))
        return destinationDirectory.appendingPathComponent(relativePath).path
    }

    private static func copy(_ task: TaskItem) -> TaskItem {
        TaskItem(
            id: task.id,
            title: task.title,
            originalText: task.originalText,
            sourceChannel: task.sourceChannel,
            assignee: task.assignee,
            deadline: task.deadline,
            status: task.status,
            parseState: task.parseState,
            confidence: task.confidence,
            needsReview: task.needsReview,
            isImportant: task.isImportant,
            isArchived: task.isArchived,
            audioFilePath: task.audioFilePath,
            screenshotFilePath: task.screenshotFilePath,
            transcriptText: task.transcriptText,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            nextReminderAt: task.nextReminderAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            parsedAt: task.parsedAt,
            parseBaseDate: task.parseBaseDate
        )
    }

    private static func rebuildContainerFromSnapshot(
        schema: Schema,
        storeURL: URL,
        originalError: Error
    ) throws -> ModelContainer {
        do {
            let backupDirectory = try backupExistingStoreFiles(storeURL: storeURL)
            try removeExistingStoreFiles(storeURL: storeURL)

            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            TaskSnapshotStore.importIfNeeded(modelContext: context)
            AppLog.persistence.info("task_store_rebuilt_from_snapshot path=\(storeURL.path, privacy: .public) backupDirectory=\(backupDirectory?.path ?? "none", privacy: .public)")
            return container
        } catch {
            AppLog.persistence.error("task_store_rebuild_failed path=\(storeURL.path, privacy: .public) originalError=\(String(describing: originalError), privacy: .public) rebuildError=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func backupExistingStoreFiles(storeURL: URL) throws -> URL? {
        let files = storeFiles(for: storeURL).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else {
            AppLog.persistence.info("task_store_backup_skipped reason=no_store_files path=\(storeURL.path, privacy: .public)")
            return nil
        }

        let backupRoot = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("StoreBackups", isDirectory: true)
        let backupDirectory = backupRoot.appendingPathComponent(backupName(), isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for file in files {
            let destination = backupDirectory.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destination)
        }

        AppLog.persistence.info("task_store_backup_created fileCount=\(files.count, privacy: .public) backupDirectory=\(backupDirectory.path, privacy: .public)")
        return backupDirectory
    }

    private static func removeExistingStoreFiles(storeURL: URL) throws {
        let files = storeFiles(for: storeURL)
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
            AppLog.persistence.info("task_store_file_removed fileName=\(file.lastPathComponent, privacy: .public)")
        }
    }

    private static func storeFiles(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }

    private static func backupName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
