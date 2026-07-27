import SwiftData
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @Bindable var appState: AppState
    let modelContainer: ModelContainer

    @State private var draftText = ""
    @State private var configurationStatus = ConfigurationStatusProvider().currentStatus()
    @State private var taskPendingDeletion: TaskItem?

    private var recentTasks: [TaskItem] {
        Array(tasks.filter { !$0.isArchived }.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            capturePanel
                .padding(14)

            Divider()

            quickReminderPanel
                .padding(14)

            Divider()

            recentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .confirmationDialog(
            "删除这个任务？",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            ),
            presenting: taskPendingDeletion
        ) { task in
            if task.audioFilePath != nil {
                Button("删除任务，保留音频") {
                    delete(task, deleteAudioFile: false)
                }

                Button("删除任务并删除音频文件", role: .destructive) {
                    delete(task, deleteAudioFile: true)
                }
            } else {
                Button("删除", role: .destructive) {
                    delete(task, deleteAudioFile: false)
                }
            }

            Button("取消", role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: { task in
            if let audioFilePath = task.audioFilePath {
                Text("这个任务关联了录音文件：\(URL(fileURLWithPath: audioFilePath).lastPathComponent)。默认只删除任务记录，保留音频文件。")
            } else {
                Text("这个操作只会删除任务记录。")
            }
        }
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MindAnchor")
                        .font(.headline)
                    Text(appState.isRecording ? "正在录音" : "快速捕获任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isRecording ? .red : .accentColor)
                .disabled(appState.isCapturing)
                .help(appState.isRecording ? "停止录音并转成任务" : "开始录音")
            }

            ConfigurationStatusView(status: configurationStatus)

            TextField("输入任务或提醒内容", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitText)

            HStack(spacing: 8) {
                Button {
                    submitText()
                } label: {
                    Label("录入", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isCapturing || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = appState.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .onAppear {
            configurationStatus = ConfigurationStatusProvider().currentStatus()
        }
    }

    private var quickReminderPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷提醒")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                QuickReminderButton(title: "5分", systemImage: "timer") {
                    createQuickReminder(minutes: 5)
                }
                QuickReminderButton(title: "15分", systemImage: "timer") {
                    createQuickReminder(minutes: 15)
                }
                QuickReminderButton(title: "1时", systemImage: "clock") {
                    createQuickReminder(minutes: 60)
                }
                QuickReminderButton(title: "下班", systemImage: "sunset") {
                    createEndOfWorkdayReminder()
                }
            }
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近任务")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if recentTasks.isEmpty {
                ContentUnavailableView("还没有任务", systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentTasks, id: \.id) { task in
                            MenuBarTaskCard(
                                task: task,
                                onComplete: {
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                                        updateStatus(task, status: .done)
                                    }
                                },
                                onDelete: {
                                    taskPendingDeletion = task
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .offset(x: 70).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.visible)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: recentTasks.map(\.id))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.setActivationPolicy(.regular)
                MainWindowPresenter.shared.show(appState: appState, modelContainer: modelContainer)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Inbox", systemImage: "rectangle.split.2x1")
            }

            Spacer()

            Button {
                AppRuntime.shared.showSettingsWindow()
                configurationStatus = ConfigurationStatusProvider().currentStatus()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Button {
                MainWindowPresenter.shared.show(appState: appState, modelContainer: modelContainer)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("打开主窗口")
        }
    }

    private func submitText() {
        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            do {
                try await appState.capturePipeline.captureText(draftText, modelContext: modelContext)
                draftText = ""
            } catch {
                appState.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func toggleRecording() {
        if appState.isRecording {
            stopRecordingAndCapture()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            do {
                try await appState.startRecording(surface: "menubar", trigger: "button") { session in
                    captureRecordingSession(session, reason: "auto_stop")
                }
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("recording_start_failed platform=macOS surface=menubar error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func stopRecordingAndCapture() {
        guard let session = appState.stopRecording(surface: "menubar", reason: "manual_toggle") else { return }
        captureRecordingSession(session, reason: "manual_toggle")
    }

    private func captureRecordingSession(_ session: RecordingSession, reason: String) {
        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            do {
                try await appState.capturePipeline.captureAudio(audioFile: session.audioURL, modelContext: modelContext)
                AppLog.capture.info("recording_capture_completed surface=menubar reason=\(reason, privacy: .public) processId=\(session.processId.uuidString, privacy: .public) sourceSurface=\(session.surface, privacy: .public)")
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("recording_capture_failed surface=menubar reason=\(reason, privacy: .public) processId=\(session.processId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func createQuickReminder(minutes: Int) {
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        createQuickReminder(deadline: deadline)
    }

    private func createEndOfWorkdayReminder() {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = 18
        components.minute = 0
        let todaySix = Calendar.current.date(from: components) ?? now.addingTimeInterval(60 * 60)
        let deadline = todaySix > now ? todaySix : now.addingTimeInterval(60 * 60)
        createQuickReminder(deadline: deadline)
    }

    private func createQuickReminder(deadline: Date) {
        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            do {
                try await appState.capturePipeline.createQuickReminder(
                    title: draftText,
                    deadline: deadline,
                    modelContext: modelContext
                )
                draftText = ""
            } catch {
                appState.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateStatus(_ task: TaskItem, status: TaskStatus) {
        do {
            try TaskRepository(modelContext: modelContext).updateStatus(task, status: status)
        } catch {
            AppLog.persistence.error("task_status_update_failed taskId=\(task.id.uuidString, privacy: .public) surface=menubar status=\(status.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func delete(_ task: TaskItem, deleteAudioFile: Bool) {
        do {
            try TaskRepository(modelContext: modelContext).delete(task, deleteAudioFile: deleteAudioFile)
            taskPendingDeletion = nil
        } catch {
            AppLog.persistence.error("task_delete_failed taskId=\(task.id.uuidString, privacy: .public) surface=menubar error=\(String(describing: error), privacy: .public)")
            appState.lastErrorMessage = error.localizedDescription
            taskPendingDeletion = nil
        }
    }
}

private struct ConfigurationStatusView: View {
    let status: ConfigurationStatus

    var body: some View {
        HStack(spacing: 8) {
            StatusPill(title: "STT", isReady: status.sttConfigured)
            StatusPill(title: "LLM", isReady: status.llmConfigured)
            Spacer()
        }
    }
}

private struct StatusPill: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isReady ? .green : .orange)
                .frame(width: 7, height: 7)
            Text("\(title) \(isReady ? "已配置" : "未配置")")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

private struct QuickReminderButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

private struct MenuBarTaskCard: View {
    let task: TaskItem
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DeadlineMiniRing(task: task)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(task.sourceChannel.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    if task.isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                    }

                    Spacer(minLength: 4)

                    Text(task.status.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.70))
                }

                Text(task.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 5) {
                    Image(systemName: task.deadline == nil ? "text.badge.checkmark" : "clock")
                        .font(.caption2.weight(.semibold))
                    Text(secondaryText)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.70))
            }

            VStack(spacing: 8) {
                Button(action: onComplete) {
                    Image(systemName: task.status == .done ? "checkmark.seal.fill" : "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(task.status == .done ? 0.28 : 0.16), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(task.status == .done)
                .help(task.status == .done ? "已完成" : "完成任务")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("删除任务")
            }
        }
        .padding(12)
        .frame(minHeight: 82)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            MiniTimelineBar(task: task)
                .frame(height: 3)
                .padding(.horizontal, 13)
                .padding(.bottom, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.28, green: 0.34, blue: 0.62).opacity(0.16), radius: 10, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.985 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.66)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.56)) {
                        isPressed = false
                    }
                }
        )
        .contextMenu {
            Button("完成") {
                onComplete()
            }
            .disabled(task.status == .done)

            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }

    private var secondaryText: String {
        if let deadline = task.deadline {
            return DisplayFormatters.deadline.string(from: deadline)
        }
        if let assignee = task.assignee, !assignee.isEmpty {
            return "相关人 \(assignee)"
        }
        return task.parseState.displayName
    }

    private var cardGradient: LinearGradient {
        let blue = Color(red: 0.38, green: 0.61, blue: 0.96)
        let indigo = Color(red: 0.50, green: 0.58, blue: 0.94)
        let violet = Color(red: 0.70, green: 0.58, blue: 0.93)
        let coral = Color(red: 0.96, green: 0.55, blue: 0.50)

        switch task.urgency {
        case .overdue:
            return LinearGradient(colors: [coral, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .soon:
            return LinearGradient(colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .normal:
            return LinearGradient(colors: [blue, violet.opacity(0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct DeadlineMiniRing: View {
    let task: TaskItem

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.74), value: progress)

            Image(systemName: task.deadline == nil ? "sparkle" : "clock")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private var progress: CGFloat {
        guard let deadline = task.deadline else { return 0.30 }
        let total = max(deadline.timeIntervalSince(task.createdAt), 60)
        let remaining = max(deadline.timeIntervalSinceNow, 0)
        return min(max(remaining / total, 0), 1)
    }

    private var ringColor: Color {
        switch task.urgency {
        case .normal: Color(red: 0.78, green: 0.96, blue: 1.00)
        case .soon: Color(red: 1.00, green: 0.89, blue: 0.58)
        case .overdue: Color(red: 1.00, green: 0.70, blue: 0.62)
        }
    }
}

private struct MiniTimelineBar: View {
    let task: TaskItem

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(timelineGradient)
                    .frame(width: max(8, proxy.size.width * progress))
                    .animation(.spring(response: 0.5, dampingFraction: 0.78), value: progress)
            }
        }
    }

    private var progress: CGFloat {
        guard let deadline = task.deadline else { return 0.18 }
        let total = max(deadline.timeIntervalSince(task.createdAt), 60)
        let elapsed = Date().timeIntervalSince(task.createdAt)
        return min(max(elapsed / total, 0), 1)
    }

    private var timelineGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.72, green: 0.94, blue: 1.00),
                task.urgency == .overdue ? Color(red: 1.00, green: 0.70, blue: 0.62) : Color(red: 0.94, green: 0.82, blue: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct CompactTaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(task.urgency.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(task.status.displayName)
                    Text(task.sourceChannel.displayName)
                    if let deadline = task.deadline {
                        Text(DisplayFormatters.deadline.string(from: deadline))
                    } else {
                        Text(task.parseState.displayName)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 5)
    }
}
