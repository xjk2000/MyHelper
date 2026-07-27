import Foundation
import Observation

struct RecordingSession {
    let processId: UUID
    let audioURL: URL
    let surface: String
    let trigger: String
}

@MainActor
@Observable
final class AppState {
    var isCapturing = false
    var isRecording = false
    var recordingStartedAt: Date?
    var lastErrorMessage: String?
    var activeRecordingProcessId: UUID?
    var activeRecordingURL: URL?
    var activeRecordingSurface: String?
    var activeRecordingTrigger: String?

    let capturePipeline: CapturePipeline
    let audioRecorder: AudioRecorder
    let globalHotkeyManager: GlobalHotkeyManager

    private var recordingAutoStopTask: Task<Void, Never>?

    init(capturePipeline: CapturePipeline? = nil) {
        self.capturePipeline = capturePipeline
            ?? CapturePipeline(notificationScheduler: UserNotificationScheduler())
        self.audioRecorder = AudioRecorder()
        self.globalHotkeyManager = GlobalHotkeyManager()
    }

    func startRecording(
        surface: String,
        trigger: String,
        onAutoStop: @escaping @MainActor (RecordingSession) -> Void
    ) async throws {
        guard !isRecording, activeRecordingProcessId == nil, !isCapturing else {
            AppLog.capture.info("recording_start_skipped surface=\(surface, privacy: .public) trigger=\(trigger, privacy: .public) reason=busy")
            return
        }

        let granted = await audioRecorder.requestMicrophoneAccess()
        guard granted else {
            lastErrorMessage = "麦克风权限未开启"
            AppLog.capture.error("recording_start_failed surface=\(surface, privacy: .public) trigger=\(trigger, privacy: .public) reason=microphone_denied")
            return
        }

        let processId = UUID()
        let audioURL = try audioRecorder.start(processId: processId)
        activeRecordingProcessId = processId
        activeRecordingURL = audioURL
        activeRecordingSurface = surface
        activeRecordingTrigger = trigger
        isRecording = true
        recordingStartedAt = Date()
        lastErrorMessage = nil
        scheduleAutoStop(processId: processId, onAutoStop: onAutoStop)
        AppLog.capture.info("recording_session_started surface=\(surface, privacy: .public) trigger=\(trigger, privacy: .public) processId=\(processId.uuidString, privacy: .public)")
    }

    func stopRecording(surface: String, reason: String) -> RecordingSession? {
        guard let processId = activeRecordingProcessId, let audioURL = activeRecordingURL else {
            isRecording = false
            recordingStartedAt = nil
            activeRecordingSurface = nil
            activeRecordingTrigger = nil
            AppLog.capture.info("recording_stop_skipped surface=\(surface, privacy: .public) reason=\(reason, privacy: .public) cause=no_active_session")
            return nil
        }

        let session = RecordingSession(
            processId: processId,
            audioURL: audioURL,
            surface: activeRecordingSurface ?? "unknown",
            trigger: activeRecordingTrigger ?? "unknown"
        )

        audioRecorder.stop(processId: processId)
        clearRecordingSession()
        AppLog.capture.info("recording_session_stopped surface=\(surface, privacy: .public) reason=\(reason, privacy: .public) processId=\(processId.uuidString, privacy: .public)")
        return session
    }

    func cancelPendingRecordingStart() {
        recordingAutoStopTask?.cancel()
        recordingAutoStopTask = nil
    }

    private func scheduleAutoStop(
        processId: UUID,
        onAutoStop: @escaping @MainActor (RecordingSession) -> Void
    ) {
        recordingAutoStopTask?.cancel()
        let maximumRecordingSeconds = RecordingSettings.maximumRecordingSeconds
        recordingAutoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(maximumRecordingSeconds))
            await MainActor.run {
                guard let self, self.activeRecordingProcessId == processId else {
                    AppLog.capture.info("recording_auto_stop_skipped processId=\(processId.uuidString, privacy: .public) reason=session_changed_or_stopped")
                    return
                }

                self.lastErrorMessage = "录音已达到 \(maximumRecordingSeconds) 秒，已自动停止"
                guard let session = self.stopRecording(surface: "auto_stop", reason: "max_duration") else { return }
                onAutoStop(session)
            }
        }
    }

    private func clearRecordingSession() {
        activeRecordingProcessId = nil
        activeRecordingURL = nil
        activeRecordingSurface = nil
        activeRecordingTrigger = nil
        isRecording = false
        recordingStartedAt = nil
        recordingAutoStopTask?.cancel()
        recordingAutoStopTask = nil
    }
}
