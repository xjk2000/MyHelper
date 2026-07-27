import AppKit
import SwiftData

@MainActor
final class GlobalHotkeyManager {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var optionIsHeld = false
    private var optionLongPressTask: Task<Void, Never>?

    private let hotkeyKeyCode: UInt16 = 49 // Space
    private let optionLongPressDelayMilliseconds = 180

    func start(appState: AppState, modelContainer: ModelContainer) {
        stop()

        let mode = RecordingHotkeyMode.current
        guard mode != .none else {
            AppLog.capture.info("global_hotkey_disabled mode=\(mode.rawValue, privacy: .public)")
            return
        }

        if mode.enablesOptionSpace {
            keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self, weak appState] event in
                Task { @MainActor in
                    guard let self, let appState else { return }
                    await self.handleKeyDown(event, appState: appState, modelContainer: modelContainer, surface: "global")
                }
            }

            keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self, weak appState] event in
                Task { @MainActor in
                    guard let self, let appState else { return }
                    self.handleKeyUp(event, appState: appState, modelContainer: modelContainer, surface: "global")
                }
            }

            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak appState] event in
                guard let self, let appState else { return event }
                Task { @MainActor in
                    await self.handleKeyDown(event, appState: appState, modelContainer: modelContainer, surface: "local")
                }
                return event
            }

            localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self, weak appState] event in
                guard let self, let appState else { return event }
                Task { @MainActor in
                    self.handleKeyUp(event, appState: appState, modelContainer: modelContainer, surface: "local")
                }
                return event
            }
        }

        if mode.enablesHoldOption {
            flagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self, weak appState] event in
                Task { @MainActor in
                    guard let self, let appState else { return }
                    self.handleFlagsChanged(event, appState: appState, modelContainer: modelContainer, surface: "global")
                }
            }

            localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self, weak appState] event in
                guard let self, let appState else { return event }
                Task { @MainActor in
                    self.handleFlagsChanged(event, appState: appState, modelContainer: modelContainer, surface: "local")
                }
                return event
            }
        }

        AppLog.capture.info("global_hotkey_started mode=\(mode.rawValue, privacy: .public) longPressDelayMs=\(self.optionLongPressDelayMilliseconds, privacy: .public) maxSeconds=\(RecordingSettings.maximumRecordingSeconds, privacy: .public)")
    }

    func stop() {
        [
            keyDownMonitor,
            keyUpMonitor,
            flagsChangedMonitor,
            localKeyDownMonitor,
            localKeyUpMonitor,
            localFlagsChangedMonitor
        ]
        .compactMap { $0 }
        .forEach(NSEvent.removeMonitor)
        keyDownMonitor = nil
        keyUpMonitor = nil
        flagsChangedMonitor = nil
        localKeyDownMonitor = nil
        localKeyUpMonitor = nil
        localFlagsChangedMonitor = nil
        optionLongPressTask?.cancel()
        optionLongPressTask = nil
    }

    private func handleKeyDown(
        _ event: NSEvent,
        appState: AppState,
        modelContainer: ModelContainer,
        surface: String
    ) async {
        guard isHotkey(event), !event.isARepeat else { return }
        optionLongPressTask?.cancel()
        optionLongPressTask = nil
        await startRecordingIfPossible(
            appState: appState,
            modelContainer: modelContainer,
            surface: surface,
            trigger: "option_space"
        )
    }

    private func startRecordingIfPossible(
        appState: AppState,
        modelContainer: ModelContainer,
        surface: String,
        trigger: String
    ) async {
        guard !appState.isRecording, appState.activeRecordingProcessId == nil, !appState.isCapturing else {
            AppLog.capture.info("global_hotkey_start_skipped surface=\(surface, privacy: .public) reason=busy")
            return
        }

        do {
            try await appState.startRecording(surface: surface, trigger: trigger) { session in
                self.captureRecordingSession(session, appState: appState, modelContainer: modelContainer, reason: "auto_stop")
            }
            AppLog.capture.info("global_hotkey_recording_started surface=\(surface, privacy: .public) trigger=\(trigger, privacy: .public)")
        } catch {
            appState.lastErrorMessage = error.localizedDescription
            AppLog.capture.error("global_hotkey_start_failed surface=\(surface, privacy: .public) trigger=\(trigger, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func handleKeyUp(
        _ event: NSEvent,
        appState: AppState,
        modelContainer: ModelContainer,
        surface: String
    ) {
        guard isHotkey(event), appState.activeRecordingProcessId != nil, appState.activeRecordingTrigger == "option_space" else { return }
        AppLog.capture.info("global_hotkey_recording_stop_requested surface=\(surface, privacy: .public)")
        stopRecordingAndCapture(appState: appState, modelContainer: modelContainer, reason: "key_up")
    }

    private func handleFlagsChanged(
        _ event: NSEvent,
        appState: AppState,
        modelContainer: ModelContainer,
        surface: String
    ) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let optionDown = flags.contains(.option)

        if optionDown && !optionIsHeld {
            optionIsHeld = true
            scheduleOptionLongPressStart(appState: appState, modelContainer: modelContainer, surface: surface)
            return
        }

        if !optionDown && optionIsHeld {
            optionIsHeld = false
            optionLongPressTask?.cancel()
            optionLongPressTask = nil

            guard appState.activeRecordingProcessId != nil, appState.activeRecordingTrigger == "hold_option" else { return }
            AppLog.capture.info("global_hotkey_recording_stop_requested surface=\(surface, privacy: .public) trigger=hold_option")
            stopRecordingAndCapture(appState: appState, modelContainer: modelContainer, reason: "option_released")
        }
    }

    private func scheduleOptionLongPressStart(
        appState: AppState,
        modelContainer: ModelContainer,
        surface: String
    ) {
        optionLongPressTask?.cancel()
        optionLongPressTask = Task { [weak self, weak appState] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(self.optionLongPressDelayMilliseconds))

            await MainActor.run {
                guard let appState, self.optionIsHeld else {
                    AppLog.capture.info("global_hotkey_start_skipped surface=\(surface, privacy: .public) trigger=hold_option reason=released_before_threshold")
                    return
                }

                Task { @MainActor in
                    await self.startRecordingIfPossible(
                        appState: appState,
                        modelContainer: modelContainer,
                        surface: surface,
                        trigger: "hold_option"
                    )
                }
            }
        }
    }

    private func stopRecordingAndCapture(appState: AppState, modelContainer: ModelContainer, reason: String) {
        guard let session = appState.stopRecording(surface: "global_hotkey", reason: reason) else { return }
        captureRecordingSession(session, appState: appState, modelContainer: modelContainer, reason: reason)
    }

    private func captureRecordingSession(
        _ session: RecordingSession,
        appState: AppState,
        modelContainer: ModelContainer,
        reason: String
    ) {
        Task { @MainActor in
            appState.isCapturing = true
            defer { appState.isCapturing = false }

            do {
                let modelContext = ModelContext(modelContainer)
                try await appState.capturePipeline.captureAudio(audioFile: session.audioURL, modelContext: modelContext)
                AppLog.capture.info("global_hotkey_capture_completed processId=\(session.processId.uuidString, privacy: .public) reason=\(reason, privacy: .public) sourceSurface=\(session.surface, privacy: .public)")
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("global_hotkey_capture_failed processId=\(session.processId.uuidString, privacy: .public) reason=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func isHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == hotkeyKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
    }
}
