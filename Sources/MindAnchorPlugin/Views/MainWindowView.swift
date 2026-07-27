import AppKit
import SwiftData
import SwiftUI

struct MainWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @Bindable var appState: AppState
    @State private var workspace: MainWorkspace = .inbox
    @State private var selectedMailbox: InboxMailbox = .recent
    @State private var selectedTask: TaskItem?
    @State private var taskPendingDeletion: TaskItem?
    @State private var draftText = ""

    var body: some View {
        Group {
            switch workspace {
            case .inbox:
                inboxWorkspace
            case .sprint:
                SprintBoardView(tasks: tasks)
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("工作区", selection: $workspace) {
                    ForEach(MainWorkspace.allCases) { workspace in
                        Text(workspace.displayName).tag(workspace)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            ToolbarItem {
                Button {
                    AppRuntime.shared.showSettingsWindow()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }

            ToolbarItem {
                Button {
                    submitText()
                } label: {
                    Label("录入文本", systemImage: "text.badge.plus")
                }
                .disabled(appState.isCapturing)
            }

            ToolbarItem {
                Button {
                    captureClipboard()
                } label: {
                    Label("剪贴板录入", systemImage: "doc.on.clipboard")
                }
                .disabled(appState.isCapturing)
            }

            ToolbarItem {
                Button {
                    captureScreenshotOCR()
                } label: {
                    Label("截图识别", systemImage: "viewfinder")
                }
                .disabled(appState.isCapturing)
            }

            ToolbarItem {
                Button {
                    if let selectedTask {
                        archive(selectedTask, isArchived: !selectedTask.isArchived)
                    }
                } label: {
                    Label(selectedTask?.isArchived == true ? "取消归档" : "归档", systemImage: selectedTask?.isArchived == true ? "tray.and.arrow.up" : "archivebox")
                }
                .disabled(workspace != .inbox || selectedTask == nil)
            }

            ToolbarItem {
                Button(role: .destructive) {
                    if let selectedTask {
                        taskPendingDeletion = selectedTask
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(workspace != .inbox || selectedTask == nil)
            }
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
        .onAppear {
            selectFallbackTaskIfNeeded()
        }
        .onChange(of: tasks.map(\.id)) { _, _ in
            selectFallbackTaskIfNeeded()
        }
        .onChange(of: selectedMailbox) { _, _ in
            selectFallbackTaskIfNeeded()
        }
    }

    private var visibleInboxTasks: [TaskItem] {
        tasks.filter { selectedMailbox.includes($0) }
    }

    private var inboxWorkspace: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                CaptureInputPanel(
                    draftText: $draftText,
                    isCapturing: appState.isCapturing,
                    isRecording: appState.isRecording,
                    recordingStartedAt: appState.recordingStartedAt,
                    errorMessage: appState.lastErrorMessage,
                    onSubmitText: submitText,
                    onToggleRecording: toggleRecording
                )
                .padding()

                InboxMailboxList(selection: $selectedMailbox, tasks: tasks)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleInboxTasks) { task in
                            TaskRowView(task: task, isSelected: selectedTask?.id == task.id)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture {
                                    selectedTask = task
                                    AppLog.app.info("task_selected surface=main_window taskId=\(task.id.uuidString, privacy: .public)")
                                }
                                .contextMenu {
                                    Button(task.isImportant ? "取消重要" : "标为重要") {
                                        updateImportance(task, isImportant: !task.isImportant)
                                    }
                                    Button(task.isArchived ? "移回最近" : "归档") {
                                        archive(task, isArchived: !task.isArchived)
                                    }
                                    Button("删除", role: .destructive) {
                                        taskPendingDeletion = task
                                    }
                                }
                        }

                        if visibleInboxTasks.isEmpty {
                            ContentUnavailableView(selectedMailbox.emptyTitle, systemImage: selectedMailbox.systemImage)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if let selectedTask {
                TaskEditorView(task: selectedTask, appState: appState) {
                    taskPendingDeletion = selectedTask
                }
            } else {
                ContentUnavailableView("选择一个任务", systemImage: "tray")
            }
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

    private func captureClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            appState.lastErrorMessage = "剪贴板没有可录入的纯文本"
            AppLog.capture.info("clipboard_capture_skipped platform=macOS reason=no_plain_text")
            return
        }

        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            do {
                try await appState.capturePipeline.captureText(text, modelContext: modelContext)
                AppLog.capture.info("clipboard_capture_completed platform=macOS inputLength=\(text.count, privacy: .public)")
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("clipboard_capture_failed platform=macOS error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func captureScreenshotOCR() {
        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            let processId = UUID()
            do {
                let result = try await ScreenCaptureOCRService().captureAndRecognize(processId: processId)
                try await appState.capturePipeline.captureScreenshotText(
                    result.text,
                    screenshotURL: result.screenshotURL,
                    modelContext: modelContext
                )
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("screenshot_capture_failed platform=macOS processId=\(processId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
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
                try await appState.startRecording(surface: "main_window", trigger: "button") { session in
                    captureRecordingSession(session, reason: "auto_stop")
                }
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("recording_start_failed platform=macOS error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func stopRecordingAndCapture() {
        guard let session = appState.stopRecording(surface: "main_window", reason: "manual_toggle") else { return }
        captureRecordingSession(session, reason: "manual_toggle")
    }

    private func captureRecordingSession(_ session: RecordingSession, reason: String) {
        Task {
            appState.isCapturing = true
            appState.lastErrorMessage = nil
            defer { appState.isCapturing = false }

            do {
                try await appState.capturePipeline.captureAudio(audioFile: session.audioURL, modelContext: modelContext)
                AppLog.capture.info("recording_capture_completed surface=main_window reason=\(reason, privacy: .public) processId=\(session.processId.uuidString, privacy: .public) sourceSurface=\(session.surface, privacy: .public)")
            } catch {
                appState.lastErrorMessage = error.localizedDescription
                AppLog.capture.error("recording_capture_failed surface=main_window reason=\(reason, privacy: .public) processId=\(session.processId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func delete(_ task: TaskItem, deleteAudioFile: Bool) {
        do {
            try TaskRepository(modelContext: modelContext).delete(task, deleteAudioFile: deleteAudioFile)
            if selectedTask?.id == task.id {
                selectedTask = nil
            }
            taskPendingDeletion = nil
        } catch {
            AppLog.persistence.error("task_delete_failed taskId=\(task.id.uuidString, privacy: .public) surface=main_window error=\(String(describing: error), privacy: .public)")
            appState.lastErrorMessage = error.localizedDescription
            if selectedTask?.id == task.id {
                selectedTask = nil
            }
            taskPendingDeletion = nil
        }
    }

    private func updateImportance(_ task: TaskItem, isImportant: Bool) {
        do {
            try TaskRepository(modelContext: modelContext).updateImportance(task, isImportant: isImportant)
        } catch {
            appState.lastErrorMessage = error.localizedDescription
            AppLog.persistence.error("task_importance_update_failed taskId=\(task.id.uuidString, privacy: .public) surface=main_window isImportant=\(isImportant, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func archive(_ task: TaskItem, isArchived: Bool) {
        do {
            try TaskRepository(modelContext: modelContext).updateArchiveState(task, isArchived: isArchived)
            if !selectedMailbox.includes(task) {
                selectedTask = nil
                selectFallbackTaskIfNeeded()
            }
        } catch {
            appState.lastErrorMessage = error.localizedDescription
            AppLog.persistence.error("task_archive_update_failed taskId=\(task.id.uuidString, privacy: .public) surface=main_window isArchived=\(isArchived, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func selectFallbackTaskIfNeeded() {
        guard selectedTask == nil || !visibleInboxTasks.contains(where: { $0.id == selectedTask?.id }) else { return }
        selectedTask = visibleInboxTasks.first
        AppLog.app.info("task_selection_fallback_applied surface=main_window taskId=\(selectedTask?.id.uuidString ?? "nil", privacy: .public) reason=missing_selection")
    }
}

private enum InboxMailbox: String, CaseIterable, Identifiable {
    case recent
    case important
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近"
        case .important: "重要"
        case .archived: "归档任务"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "tray"
        case .important: "star"
        case .archived: "archivebox"
        }
    }

    var emptyTitle: String {
        switch self {
        case .recent: "没有最近任务"
        case .important: "没有重要任务"
        case .archived: "没有归档任务"
        }
    }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .recent:
            return !task.isArchived
        case .important:
            return task.isImportant && !task.isArchived
        case .archived:
            return task.isArchived
        }
    }
}

private struct InboxMailboxList: View {
    @Binding var selection: InboxMailbox
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("智能任务")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            VStack(spacing: 3) {
                ForEach(InboxMailbox.allCases) { mailbox in
                    Button {
                        selection = mailbox
                        AppLog.app.info("inbox_mailbox_selected mailbox=\(mailbox.rawValue, privacy: .public)")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mailbox.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 18)
                            Text(mailbox.title)
                                .font(.callout.weight(selection == mailbox ? .semibold : .regular))
                            Spacer()
                            Text("\(count(for: mailbox))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selection == mailbox ? .white.opacity(0.92) : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(selection == mailbox ? .white.opacity(0.16) : .primary.opacity(0.07), in: Capsule())
                        }
                        .foregroundStyle(selection == mailbox ? .white : .primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(selection == mailbox ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func count(for mailbox: InboxMailbox) -> Int {
        tasks.filter { mailbox.includes($0) }.count
    }
}

private enum MainWorkspace: String, CaseIterable, Identifiable {
    case inbox
    case sprint

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .sprint: "Sprint"
        }
    }
}

private struct CaptureInputPanel: View {
    @Binding var draftText: String

    let isCapturing: Bool
    let isRecording: Bool
    let recordingStartedAt: Date?
    let errorMessage: String?
    let onSubmitText: () -> Void
    let onToggleRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Inbox")
                    .font(.title3.weight(.semibold))
                if isRecording {
                    Text("录音中")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                recordButton
            }

            TextEditor(text: $draftText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 80, maxHeight: 96)
                .background(.background.opacity(0.70), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }

            HStack(spacing: 10) {
                Button {
                    onSubmitText()
                } label: {
                    Label("录入任务", systemImage: "arrow.down.doc")
                }
                .buttonStyle(CaptureActionButtonStyle(isPrimary: true))
                .disabled(isCapturing || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var recordButton: some View {
        Button {
            onToggleRecording()
        } label: {
            Label(isRecording ? "停止录音" : "开始录音", systemImage: isRecording ? "stop.fill" : "mic.fill")
        }
        .buttonStyle(CaptureActionButtonStyle(isPrimary: isRecording))
        .disabled(isCapturing)
    }
}

private struct CaptureActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .foregroundStyle(isPrimary ? .white : .primary)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isPrimary ? Color.white.opacity(0.16) : Color.primary.opacity(0.09), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.76), value: configuration.isPressed)
    }

    private func background(isPressed: Bool) -> Color {
        if isPrimary {
            return Color.accentColor.opacity(isPressed ? 0.86 : 0.95)
        }
        return Color.primary.opacity(isPressed ? 0.09 : 0.055)
    }
}

private struct TaskEditorView: View {
    @Environment(\.modelContext) private var modelContext

    let task: TaskItem
    let appState: AppState
    let onDelete: () -> Void

    @State private var title: String = ""
    @State private var originalText: String = ""
    @State private var sourceChannel: SourceChannel = .unknown
    @State private var assignee: String = ""
    @State private var deadline: Date = Date()
    @State private var hasDeadline = false
    @State private var status: TaskStatus = .todo
    @State private var needsReview = true
    @State private var parseReviewed = false
    @State private var isImportant = false
    @State private var isArchived = false
    @State private var saveMessage: String?
    @State private var isRetrying = false
    @State private var isLoadingTaskState = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleHeader

                DetailSection {
                    VStack(spacing: 0) {
                        EditorFieldRow("状态") {
                            Picker("状态", selection: $status) {
                                ForEach(TaskStatus.allCases) { status in
                                    Text(status.displayName).tag(status)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        DetailDivider()

                        EditorFieldRow("来源") {
                            Picker("来源", selection: $sourceChannel) {
                                ForEach(SourceChannel.allCases, id: \.rawValue) { channel in
                                    Text(channel.displayName).tag(channel)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        DetailDivider()

                        EditorFieldRow("相关人") {
                            TextField("未填写", text: $assignee)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }

                        DetailDivider()

                        EditorFieldRow("重要") {
                            Toggle("", isOn: $isImportant)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        DetailDivider()

                        EditorFieldRow("已归档") {
                            Toggle("", isOn: $isArchived)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        DetailDivider()

                        EditorFieldRow("解析已确认") {
                            Toggle("已核对无误", isOn: $parseReviewed)
                                .toggleStyle(.checkbox)
                                .help("打开表示 AI 解析出的标题、来源、相关人和截止时间已人工核对")
                        }

                        DetailDivider()

                        EditorFieldRow("解析状态") {
                            Text(task.parseState.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DeadlineEditorView(
                    taskId: task.id,
                    hasDeadline: $hasDeadline,
                    deadline: $deadline
                )

                if let screenshotFilePath = task.screenshotFilePath {
                    DetailSection(title: "截图附件") {
                        HStack(spacing: 10) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text(URL(fileURLWithPath: screenshotFilePath).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Button("打开") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: screenshotFilePath))
                                AppLog.capture.info("screenshot_attachment_opened taskId=\(task.id.uuidString, privacy: .public)")
                            }
                            .buttonStyle(CaptureActionButtonStyle(isPrimary: false))
                        }
                    }
                }

                DetailSection(title: "原始内容") {
                    TextEditor(text: $originalText)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 132)
                        .background(.background.opacity(0.74), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                }

                actionBar
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .id(task.id)
        .onAppear(perform: load)
        .onChange(of: task.id) { _, _ in
            load()
        }
        .onChange(of: parseReviewed) { _, newValue in
            guard !isLoadingTaskState else { return }
            updateReviewState(isReviewed: newValue)
        }
    }

    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("任务")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextField("任务标题", text: $title)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .textFieldStyle(.plain)
                .lineLimit(2)
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                DetailBadge(title: status.displayName, systemImage: "circle.dotted", color: .accentColor)
                DetailBadge(title: sourceChannel.displayName, systemImage: "number", color: .secondary)
                if isImportant {
                    DetailBadge(title: "重要", systemImage: "star.fill", color: .yellow)
                }
                if isArchived {
                    DetailBadge(title: "已归档", systemImage: "archivebox", color: .secondary)
                }
                if needsReview {
                    DetailBadge(title: "解析待确认", systemImage: "exclamationmark.circle", color: .orange)
                } else {
                    DetailBadge(title: "解析已确认", systemImage: "checkmark.circle", color: .green)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                save()
            } label: {
                Label("保存修改", systemImage: "checkmark")
            }
            .buttonStyle(CaptureActionButtonStyle(isPrimary: true))
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                retry()
            } label: {
                Label("重试解析", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CaptureActionButtonStyle(isPrimary: false))
            .disabled(isRetrying || appState.isCapturing)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(CaptureActionButtonStyle(isPrimary: false))

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    private func load() {
        isLoadingTaskState = true
        title = task.title
        originalText = task.originalText
        sourceChannel = task.sourceChannel
        assignee = task.assignee ?? ""
        hasDeadline = task.deadline != nil
        deadline = task.deadline ?? Date()
        status = task.status
        needsReview = task.needsReview
        parseReviewed = !task.needsReview
        isImportant = task.isImportant
        isArchived = task.isArchived
        saveMessage = nil
        Task { @MainActor in
            isLoadingTaskState = false
        }
    }

    private func save() {
        do {
            try TaskRepository(modelContext: modelContext).saveEdits(
                task,
                title: title,
                originalText: originalText,
                sourceChannel: sourceChannel,
                assignee: assignee,
                deadline: hasDeadline ? deadline : nil,
                status: status,
                needsReview: !parseReviewed,
                isImportant: isImportant,
                isArchived: isArchived
            )
            needsReview = !parseReviewed
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
            AppLog.persistence.error("task_edit_save_failed taskId=\(task.id.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func retry() {
        Task {
            isRetrying = true
            appState.isCapturing = true
            saveMessage = nil
            defer {
                isRetrying = false
                appState.isCapturing = false
            }

            do {
                task.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? task.title
                    : title.trimmingCharacters(in: .whitespacesAndNewlines)
                task.sourceChannel = sourceChannel
                task.assignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                task.deadline = hasDeadline ? deadline : nil
                task.status = status
                task.isImportant = isImportant
                task.isArchived = isArchived
                try await appState.capturePipeline.retry(
                    task: task,
                    editedText: originalText,
                    modelContext: modelContext
                )
                load()
                saveMessage = "重试完成"
            } catch {
                saveMessage = "重试失败：\(error.localizedDescription)"
                AppLog.capture.error("task_retry_failed taskId=\(task.id.uuidString, privacy: .public) surface=main_window error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func updateReviewState(isReviewed: Bool) {
        do {
            try TaskRepository(modelContext: modelContext).updateReviewState(task, isReviewed: isReviewed)
            needsReview = !isReviewed
            saveMessage = isReviewed ? "解析已确认" : "已标为待确认"
        } catch {
            isLoadingTaskState = true
            parseReviewed.toggle()
            Task { @MainActor in
                isLoadingTaskState = false
            }
            saveMessage = "确认状态保存失败：\(error.localizedDescription)"
            AppLog.persistence.error("task_review_state_update_failed taskId=\(task.id.uuidString, privacy: .public) isReviewed=\(isReviewed, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct EditorFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Spacer(minLength: 12)

            content
                .font(.callout)
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .frame(minHeight: 34)
    }
}

private struct DetailDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 88)
    }
}

private struct DetailBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
