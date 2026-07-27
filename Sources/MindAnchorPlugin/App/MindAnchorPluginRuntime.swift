import AppKit
import SwiftData
import SwiftUI
import UserNotifications

public enum MindAnchorPlugin {
    @MainActor
    public static func makeSprintMenuView() -> AnyView {
        AppRuntime.shared.prepareIfNeeded()
        guard let modelContainer = AppRuntime.shared.modelContainer else {
            return AnyView(
                ContentUnavailableView(
                    "Sprint 暂不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text("MindAnchor 数据存储初始化失败")
                )
            )
        }

        return AnyView(
            SprintMenuBoardView()
                .modelContainer(modelContainer)
        )
    }

    @discardableResult
    public static func migrateLegacyDataForCurrentUser() -> Int {
        let schema = Schema([TaskItem.self])
        do {
            let container = try LocalTaskStore.makeContainer(schema: schema)
            LocalTaskStore.migrateLegacyDefaultStoreIfNeeded(to: container, schema: schema)
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<TaskItem>()).count
        } catch {
            NSLog("MindAnchor plugin failed to migrate legacy data: \(error)")
            AppLog.persistence.error("task_store_manual_migration_failed error=\(String(describing: error), privacy: .public)")
            return -1
        }
    }

    @MainActor
    @discardableResult
    public static func openMainWindow() -> Bool {
        AppRuntime.shared.prepareIfNeeded()
        AppRuntime.shared.showMainWindow()
        return true
    }

    @MainActor
    @discardableResult
    public static func openSettingsWindow() -> Bool {
        AppRuntime.shared.prepareIfNeeded()
        AppRuntime.shared.showSettingsWindow()
        return true
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    var modelContainer: ModelContainer?
    var appState: AppState?

    private var settingsWindow: NSWindow?
    private var notificationDelegate: NotificationDelegate?
    private var hasConfiguredNotifications = false
    private var hasStartedSenseVoice = false

    private init() {}

    func prepareIfNeeded() {
        if modelContainer == nil || appState == nil {
            initializeState()
        }
        configureNotificationsIfNeeded()
        startGlobalHotkeyIfPossible()
        startSenseVoiceServiceIfNeeded()
    }

    func startGlobalHotkeyIfPossible() {
        guard let appState, let modelContainer else {
            AppLog.capture.error("global_hotkey_start_skipped reason=runtime_not_ready")
            return
        }

        appState.globalHotkeyManager.start(
            appState: appState,
            modelContainer: modelContainer
        )
    }

    func showMainWindow() {
        guard let appState, let modelContainer else {
            AppLog.app.error("main_window_open_skipped reason=runtime_not_ready")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainWindowPresenter.shared.show(appState: appState, modelContainer: modelContainer)
        }
    }

    func showSettingsWindow() {
        prepareIfNeeded()
        guard let modelContainer else { return }

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MindAnchor 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .modelContainer(modelContainer)
            )
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startSenseVoiceServiceIfNeeded() {
        guard !hasStartedSenseVoice else { return }
        guard (UserDefaults.standard.string(forKey: AppSettingKey.sttProvider) ?? "tencent") == "sensevoice" else { return }
        hasStartedSenseVoice = true

        Task {
            do {
                try await SenseVoiceServiceManager.shared.ensureRunning(configuration: SenseVoiceDefaults.currentConfiguration())
                AppLog.stt.info("sensevoice_service_autostart_completed surface=myhelper_plugin")
            } catch {
                AppLog.stt.error("sensevoice_service_autostart_failed surface=myhelper_plugin error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func initializeState() {
        let schema = Schema([TaskItem.self])

        do {
            let container = try LocalTaskStore.makeContainer(schema: schema)
            LocalTaskStore.migrateLegacyDefaultStoreIfNeeded(to: container, schema: schema)
            modelContainer = container
        } catch {
            NSLog("MindAnchor plugin failed to initialize persistent SwiftData store, falling back to memory store: \(error)")
            AppLog.persistence.error("task_store_persistent_init_failed fallback=memory error=\(String(describing: error), privacy: .public)")
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
                TaskSnapshotStore.importIfNeeded(modelContext: ModelContext(container))
                modelContainer = container
                AppLog.persistence.info("task_store_memory_fallback_opened")
            } catch {
                AppLog.persistence.error("task_store_memory_fallback_failed error=\(String(describing: error), privacy: .public)")
            }
        }

        appState = AppState()
    }

    private func configureNotificationsIfNeeded() {
        guard !hasConfiguredNotifications else { return }
        hasConfiguredNotifications = true

        let done = UNNotificationAction(
            identifier: NotificationAction.markDone.rawValue,
            title: "完成",
            options: []
        )
        let snooze5 = UNNotificationAction(
            identifier: NotificationAction.snooze5Minutes.rawValue,
            title: "5分钟后再说",
            options: []
        )
        let snooze1Hour = UNNotificationAction(
            identifier: NotificationAction.snooze1Hour.rawValue,
            title: "1小时后再说",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: [snooze5, snooze1Hour, done],
            intentIdentifiers: [],
            options: []
        )

        let delegate = NotificationDelegate()
        notificationDelegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([category])
        AppLog.notification.info("notification_categories_registered category=\(NotificationCategory.taskReminder.rawValue, privacy: .public)")
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let taskId = response.notification.request.content.userInfo["taskId"] as? String ?? "unknown"
        AppLog.notification.info("notification_action_received taskId=\(taskId, privacy: .public) action=\(response.actionIdentifier, privacy: .public)")

        await NotificationActionHandler().handle(actionIdentifier: response.actionIdentifier, taskIdString: taskId)
    }
}
