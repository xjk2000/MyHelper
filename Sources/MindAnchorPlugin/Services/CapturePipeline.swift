import Foundation
import SwiftData

@MainActor
final class CapturePipeline {
    private let notificationScheduler: NotificationScheduling
    private let credentialStore: SecureCredentialStore

    init(notificationScheduler: NotificationScheduling, credentialStore: SecureCredentialStore = SecureCredentialStore()) {
        self.notificationScheduler = notificationScheduler
        self.credentialStore = credentialStore
    }

    func captureText(_ text: String, modelContext: ModelContext) async throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CaptureError.emptyInput
        }

        let processId = UUID()
        let task = TaskItem(
            title: Self.fallbackTitle(from: normalized),
            originalText: normalized,
            parseState: .pending,
            needsReview: true,
            transcriptText: normalized
        )
        modelContext.insert(task)
        try save(modelContext, taskId: task.id, stage: "insert_pending_task")

        AppLog.capture.info("capture_started platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=text inputLength=\(normalized.count, privacy: .public)")

        do {
            task.parseState = ParseState.parsing
            try save(modelContext, taskId: task.id, stage: "mark_parsing")

            try await parseAndFinalize(task: task, text: normalized, modelContext: modelContext)
        } catch {
            applyFailure(error, to: task, fallbackTitle: Self.fallbackTitle(from: normalized))
            try? save(modelContext, taskId: task.id, stage: "capture_text_failed")
            AppLog.capture.error("capture_failed platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=text error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func captureScreenshotText(_ text: String, screenshotURL: URL, modelContext: ModelContext) async throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CaptureError.emptyInput
        }

        let processId = UUID()
        let task = TaskItem(
            title: Self.fallbackTitle(from: normalized),
            originalText: normalized,
            sourceChannel: .unknown,
            parseState: .pending,
            needsReview: true,
            screenshotFilePath: screenshotURL.path,
            transcriptText: normalized
        )
        modelContext.insert(task)
        try save(modelContext, taskId: task.id, stage: "insert_pending_screenshot_task")

        AppLog.capture.info("capture_started platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=screenshot_ocr inputLength=\(normalized.count, privacy: .public) screenshotFile=\(screenshotURL.lastPathComponent, privacy: .public)")

        do {
            task.parseState = ParseState.parsing
            try save(modelContext, taskId: task.id, stage: "mark_screenshot_parsing")
            try await parseAndFinalize(task: task, text: normalized, modelContext: modelContext)
        } catch {
            applyFailure(error, to: task, fallbackTitle: Self.fallbackTitle(from: normalized))
            try? save(modelContext, taskId: task.id, stage: "capture_screenshot_failed")
            AppLog.capture.error("capture_failed platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=screenshot_ocr error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func captureAudio(audioFile: URL, modelContext: ModelContext) async throws {
        let processId = UUID()
        let task = TaskItem(
            title: "待转写录音",
            parseState: .pending,
            needsReview: true,
            audioFilePath: audioFile.path
        )
        modelContext.insert(task)
        try save(modelContext, taskId: task.id, stage: "insert_pending_audio_task")

        AppLog.capture.info("capture_started platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=audio audioFile=\(audioFile.lastPathComponent, privacy: .public)")

        do {
            task.parseState = .transcribing
            try save(modelContext, taskId: task.id, stage: "mark_transcribing")

            let transcriptionService = try makeTranscriptionService()
            let transcription = try await transcriptionService.transcribe(
                audioFile: audioFile,
                context: TranscriptionContext(
                    processId: processId,
                    platform: "macOS",
                    localeIdentifier: Locale.current.identifier,
                    maxDurationSeconds: RecordingSettings.maximumRecordingSeconds
                )
            )

            task.transcriptText = transcription.text
            task.originalText = transcription.text
            task.title = Self.fallbackTitle(from: transcription.text)
            task.parseState = .parsing
            try save(modelContext, taskId: task.id, stage: "transcription_completed")

            AppLog.stt.info("transcription_completed taskId=\(task.id.uuidString, privacy: .public) provider=\(transcription.provider, privacy: .public) transcriptLength=\(transcription.text.count, privacy: .public) durationMs=\(transcription.durationMilliseconds ?? -1, privacy: .public)")

            try await parseAndFinalize(task: task, text: transcription.text, modelContext: modelContext)
        } catch {
            applyFailure(error, to: task, fallbackTitle: task.transcriptText.map { Self.fallbackTitle(from: $0) } ?? "待整理录音")
            try? save(modelContext, taskId: task.id, stage: "capture_audio_failed")
            AppLog.capture.error("capture_failed platform=macOS processId=\(processId.uuidString, privacy: .public) taskId=\(task.id.uuidString, privacy: .public) channel=audio error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func createQuickReminder(title rawTitle: String, deadline: Date, modelContext: ModelContext) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = title.isEmpty ? "提醒" : title
        let task = TaskItem(
            title: taskTitle,
            originalText: taskTitle,
            sourceChannel: .faceToFace,
            deadline: deadline,
            parseState: .parsed,
            confidence: 1,
            needsReview: false,
            transcriptText: taskTitle
        )

        modelContext.insert(task)
        try save(modelContext, taskId: task.id, stage: "quick_reminder_created")
        AppLog.capture.info("quick_reminder_created platform=macOS taskId=\(task.id.uuidString, privacy: .public) deadline=\(deadline.ISO8601Format(), privacy: .public)")

        do {
            try await notificationScheduler.scheduleReminder(for: task)
        } catch {
            AppLog.notification.error("notification_schedule_failed taskId=\(task.id.uuidString, privacy: .public) reason=\(String(describing: error), privacy: .public)")
        }
    }

    func retry(task: TaskItem, modelContext: ModelContext) async throws {
        AppLog.capture.info("task_retry_started taskId=\(task.id.uuidString, privacy: .public) hasAudio=\((task.audioFilePath != nil), privacy: .public) transcriptLength=\((task.transcriptText?.count ?? 0), privacy: .public)")

        if let text = task.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            task.parseState = .parsing
            task.needsReview = true
            try save(modelContext, taskId: task.id, stage: "retry_mark_parsing")
            try await parseAndFinalize(task: task, text: text, modelContext: modelContext)
            return
        }

        guard let audioFilePath = task.audioFilePath else {
            AppLog.capture.error("task_retry_failed taskId=\(task.id.uuidString, privacy: .public) reason=no_transcript_or_audio")
            throw CaptureError.noRetrySource
        }

        let audioURL = URL(fileURLWithPath: audioFilePath)
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            AppLog.capture.error("task_retry_failed taskId=\(task.id.uuidString, privacy: .public) reason=audio_file_missing")
            throw CaptureError.audioFileMissing
        }

        let processId = UUID()
        do {
            task.parseState = .transcribing
            task.needsReview = true
            try save(modelContext, taskId: task.id, stage: "retry_mark_transcribing")

            let transcriptionService = try makeTranscriptionService()
            let transcription = try await transcriptionService.transcribe(
                audioFile: audioURL,
                context: TranscriptionContext(
                    processId: processId,
                    platform: "macOS",
                    localeIdentifier: Locale.current.identifier,
                    maxDurationSeconds: RecordingSettings.maximumRecordingSeconds
                )
            )

            task.transcriptText = transcription.text
            task.originalText = transcription.text
            task.title = Self.fallbackTitle(from: transcription.text)
            task.parseState = .parsing
            try save(modelContext, taskId: task.id, stage: "retry_transcription_completed")

            try await parseAndFinalize(task: task, text: transcription.text, modelContext: modelContext)
        } catch {
            applyFailure(error, to: task, fallbackTitle: task.transcriptText.map { Self.fallbackTitle(from: $0) } ?? task.title)
            try? save(modelContext, taskId: task.id, stage: "task_retry_failed")
            throw error
        }
    }

    func retry(task: TaskItem, editedText: String, modelContext: ModelContext) async throws {
        let normalized = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            AppLog.capture.error("task_retry_failed taskId=\(task.id.uuidString, privacy: .public) reason=edited_text_empty")
            throw CaptureError.emptyInput
        }

        AppLog.capture.info("task_retry_started taskId=\(task.id.uuidString, privacy: .public) source=edited_original_text inputLength=\(normalized.count, privacy: .public)")
        task.originalText = normalized
        task.transcriptText = normalized
        task.title = Self.fallbackTitle(from: normalized)
        task.parseState = .parsing
        task.needsReview = true
        task.updatedAt = Date()
        try save(modelContext, taskId: task.id, stage: "retry_mark_parsing_from_edited_text")

        try await parseAndFinalize(task: task, text: normalized, modelContext: modelContext)
    }

    private func parseAndFinalize(task: TaskItem, text: String, modelContext: ModelContext) async throws {
        let parsingService = try makeParsingService()
        let parsed = try await parsingService.parse(
            input: TaskParseInput(
                text: text,
                capturedAt: task.parseBaseDate,
                timeZoneIdentifier: TimeZone.current.identifier,
                localeIdentifier: Locale.current.identifier
            )
        )

        apply(parsed, to: task)
        try save(modelContext, taskId: task.id, stage: "parse_completed")

        do {
            try await notificationScheduler.scheduleReminder(for: task)
        } catch {
            // 通知失败不能污染已成功解析的任务；用户仍应能在 Inbox 看到结构化结果。
            AppLog.notification.error("notification_schedule_failed taskId=\(task.id.uuidString, privacy: .public) reason=\(String(describing: error), privacy: .public)")
        }
    }

    private func makeTranscriptionService() throws -> SpeechTranscriptionService {
        let provider = UserDefaults.standard.string(forKey: AppSettingKey.sttProvider) ?? "tencent"
        switch provider {
        case "mock":
            return MockTranscriptionService()
        case "sensevoice":
            return SenseVoiceLocalTranscriptionService(
                repoPath: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceRepoPath) ?? SenseVoiceDefaults.repoPath,
                pythonPath: UserDefaults.standard.string(forKey: AppSettingKey.senseVoicePythonPath) ?? SenseVoiceDefaults.pythonPath,
                modelName: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceModel) ?? SenseVoiceDefaults.model,
                device: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceDevice) ?? SenseVoiceDefaults.device,
                language: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceLanguage) ?? SenseVoiceDefaults.language,
                port: UserDefaults.standard.integer(forKey: AppSettingKey.senseVoicePort) == 0
                    ? SenseVoiceDefaults.port
                    : UserDefaults.standard.integer(forKey: AppSettingKey.senseVoicePort)
            )
        case "tencent":
            guard
                let secretId = try credentialStore.read(account: CredentialAccount.tencentSecretId), !secretId.isEmpty,
                let secretKey = try credentialStore.read(account: CredentialAccount.tencentSecretKey), !secretKey.isEmpty
            else {
                AppLog.stt.error("transcription_configuration_missing provider=tencent missing=credential")
                throw TranscriptionError.providerNotConfigured(provider: "tencent")
            }

            let engine = UserDefaults.standard.string(forKey: AppSettingKey.tencentEngine) ?? "16k_zh-PY"
            return TencentShortASRService(secretId: secretId, secretKey: secretKey, engine: engine)
        default:
            AppLog.stt.error("transcription_configuration_invalid provider=\(provider, privacy: .public)")
            throw TranscriptionError.providerNotConfigured(provider: provider)
        }
    }

    private func makeParsingService() throws -> TaskParsingService {
        let provider = UserDefaults.standard.string(forKey: AppSettingKey.llmProvider) ?? "openaiCompatible"
        switch provider {
        case "mock":
            return MockTaskParsingService()
        case "openaiCompatible", "cloud":
            let baseURL = UserDefaults.standard.string(forKey: AppSettingKey.llmBaseURL) ?? ""
            let model = UserDefaults.standard.string(forKey: AppSettingKey.llmModel) ?? ""
            guard
                !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let apiKey = try credentialStore.read(account: CredentialAccount.llmAPIKey), !apiKey.isEmpty
            else {
                AppLog.aiParse.error("parse_configuration_missing provider=openai_compatible missing=baseURL_or_model_or_apiKey")
                throw TaskParsingError.providerNotConfigured
            }

            return OpenAICompatibleTaskParsingService(baseURL: baseURL, apiKey: apiKey, model: model)
        default:
            AppLog.aiParse.error("parse_configuration_invalid provider=\(provider, privacy: .public)")
            throw TaskParsingError.providerNotConfigured
        }
    }

    private func apply(_ draft: ParsedTaskDraft, to task: TaskItem) {
        task.title = draft.title
        task.originalText = draft.originalText
        task.sourceChannel = draft.sourceChannel
        task.assignee = draft.assignee
        task.deadline = draft.deadline
        task.confidence = draft.confidence
        task.needsReview = draft.needsReview
        task.parseState = .parsed
        task.parsedAt = Date()
        task.updatedAt = Date()
    }

    private func save(_ modelContext: ModelContext, taskId: UUID, stage: String) throws {
        do {
            try modelContext.save()
            TaskSnapshotStore.exportAll(modelContext: modelContext, reason: stage)
            AppLog.persistence.info("swiftdata_save_completed taskId=\(taskId.uuidString, privacy: .public) stage=\(stage, privacy: .public)")
        } catch {
            AppLog.persistence.error("swiftdata_save_failed taskId=\(taskId.uuidString, privacy: .public) stage=\(stage, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func applyFailure(_ error: Error, to task: TaskItem, fallbackTitle: String) {
        task.parseState = .failed
        task.needsReview = true
        task.title = fallbackTitle
        task.updatedAt = Date()
    }

    private static func fallbackTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "待整理任务"
        }

        // 失败兜底标题只截取前缀，避免把整段隐私文本暴露到列表。
        return String(trimmed.prefix(28))
    }
}

enum CaptureError: LocalizedError {
    case emptyInput
    case noRetrySource
    case audioFileMissing

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入任务内容"
        case .noRetrySource:
            return "没有可重试的转写文本或录音文件"
        case .audioFileMissing:
            return "录音文件不存在，无法重试"
        }
    }
}
