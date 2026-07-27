import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingKey.sttProvider) private var sttProvider = "tencent"
    @AppStorage(AppSettingKey.tencentEngine) private var tencentEngine = "16k_zh-PY"
    @AppStorage(AppSettingKey.senseVoiceRepoPath) private var senseVoiceRepoPath = SenseVoiceDefaults.repoPath
    @AppStorage(AppSettingKey.senseVoicePythonPath) private var senseVoicePythonPath = SenseVoiceDefaults.pythonPath
    @AppStorage(AppSettingKey.senseVoiceModel) private var senseVoiceModel = SenseVoiceDefaults.model
    @AppStorage(AppSettingKey.senseVoiceDevice) private var senseVoiceDevice = SenseVoiceDefaults.device
    @AppStorage(AppSettingKey.senseVoiceLanguage) private var senseVoiceLanguage = SenseVoiceDefaults.language
    @AppStorage(AppSettingKey.senseVoicePort) private var senseVoicePort = SenseVoiceDefaults.port
    @AppStorage(AppSettingKey.llmProvider) private var llmProvider = "openaiCompatible"
    @AppStorage(AppSettingKey.llmBaseURL) private var llmBaseURL = ""
    @AppStorage(AppSettingKey.llmModel) private var llmModel = ""
    @AppStorage(AppSettingKey.defaultReminderOffsetMinutes) private var defaultReminderOffsetMinutes = 60
    @AppStorage(AppSettingKey.maximumRecordingSeconds) private var maximumRecordingSeconds = RecordingSettings.defaultMaximumSeconds
    @AppStorage(AppSettingKey.recordingHotkeyMode) private var recordingHotkeyMode = RecordingHotkeyMode.none.rawValue
    @AppStorage(AppSettingKey.audioStorageDirectory) private var audioStorageDirectory = AudioStorageDefaults.directoryPath

    @State private var tencentSecretId = ""
    @State private var tencentSecretKey = ""
    @State private var llmAPIKey = ""
    @State private var saveMessage: String?
    @State private var isTestingSTT = false
    @State private var isTestingLLM = false

    private let credentialStore = SecureCredentialStore()

    var body: some View {
        Form {
            Section("语音转文字") {
                Picker("STT 服务商", selection: $sttProvider) {
                    Text("腾讯云一句话识别").tag("tencent")
                    Text("本地 SenseVoice").tag("sensevoice")
                    Text("Mock").tag("mock")
                }

                if sttProvider == "tencent" {
                    TextField("腾讯云引擎", text: $tencentEngine)
                        .textFieldStyle(.roundedBorder)

                    TextField("SecretId", text: $tencentSecretId)
                        .textFieldStyle(.roundedBorder)

                    SecureField("SecretKey", text: $tencentSecretKey)
                        .textFieldStyle(.roundedBorder)

                    Button("保存腾讯云配置") {
                        saveTencentCredentials()
                    }
                }

                if sttProvider == "sensevoice" {
                    TextField("SenseVoice 项目路径", text: $senseVoiceRepoPath)
                        .textFieldStyle(.roundedBorder)

                    TextField("Python 路径", text: $senseVoicePythonPath)
                        .textFieldStyle(.roundedBorder)

                    TextField("模型", text: $senseVoiceModel)
                        .textFieldStyle(.roundedBorder)

                    TextField("设备 cpu / mps / cuda:0", text: $senseVoiceDevice)
                        .textFieldStyle(.roundedBorder)

                    Stepper("服务端口 \(senseVoicePort)", value: $senseVoicePort, in: 1024...65535)

                    Picker("语言", selection: $senseVoiceLanguage) {
                        Text("自动").tag("auto")
                        Text("中文").tag("zh")
                        Text("英语").tag("en")
                        Text("粤语").tag("yue")
                        Text("日语").tag("ja")
                        Text("韩语").tag("ko")
                    }

                    HStack {
                        Button("启动 / 重启本地服务") {
                            startSenseVoiceServiceIfSelected(reason: "manual_restart", forceRestart: true)
                        }

                        Text("服务地址 127.0.0.1:\(senseVoicePort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("检查 STT 配置") {
                    checkSTTConfiguration()
                }

                Button {
                    testSTTConfiguration()
                } label: {
                    if isTestingSTT {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("录音测试中")
                        }
                    } else {
                        Text("录制 3 秒并测试 STT")
                    }
                }
                .disabled(isTestingSTT)

                Text(sttHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("录音") {
                Stepper(
                    "自动停止录音 \(maximumRecordingSeconds) 秒",
                    value: $maximumRecordingSeconds,
                    in: RecordingSettings.minimumMaximumSeconds...RecordingSettings.maximumMaximumSeconds,
                    step: 5
                )

                Text("达到该时长会自动停止录音并开始转写。腾讯云一句话识别建议不超过 60 秒；本地 SenseVoice 可以按需要调长。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
                Picker("录音快捷键", selection: $recordingHotkeyMode) {
                    ForEach(RecordingHotkeyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }

                Text("默认不启用任何快捷键。选择后会立即生效；全局快捷键可能需要在系统设置中允许辅助功能权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI 解析") {
                Picker("解析服务", selection: $llmProvider) {
                    Text("OpenAI-compatible").tag("openaiCompatible")
                    Text("Mock").tag("mock")
                }

                TextField("Base URL，例如 https://api.deepseek.com/v1", text: $llmBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("模型，例如 deepseek-chat / qwen-plus", text: $llmModel)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $llmAPIKey)
                    .textFieldStyle(.roundedBorder)

                Button("保存 LLM 配置") {
                    saveLLMCredentials()
                }

                Button {
                    testLLMConfiguration()
                } label: {
                    if isTestingLLM {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("测试 LLM")
                    }
                }
                .disabled(isTestingLLM)
            }

            Section("提醒") {
                Stepper("默认提前 \(defaultReminderOffsetMinutes) 分钟", value: $defaultReminderOffsetMinutes, in: 5...1440, step: 5)
            }

            Section("文件存储") {
                TextField("录音文件目录", text: $audioStorageDirectory)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("选择目录") {
                        chooseAudioStorageDirectory()
                    }

                    Button("打开目录") {
                        openAudioStorageDirectory()
                    }

                    Button("恢复默认") {
                        audioStorageDirectory = AudioStorageDefaults.directoryPath
                        saveMessage = "录音目录已恢复为项目 Data/Recordings"
                        AppLog.capture.info("audio_storage_directory_reset directory=\(audioStorageDirectory, privacy: .public)")
                    }
                }

                Text("新录音会保存到这个目录；已存在的录音不会自动迁移。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 560)
        .onAppear {
            loadCredentials()
            migrateSenseVoicePathsIfNeeded()
            startSenseVoiceServiceIfSelected(reason: "settings_appear")
        }
        .onChange(of: sttProvider) { _, provider in
            if provider == "sensevoice" {
                startSenseVoiceServiceIfSelected(reason: "provider_changed")
            }
        }
        .onChange(of: recordingHotkeyMode) { _, mode in
            AppRuntime.shared.startGlobalHotkeyIfPossible()
            AppLog.capture.info("recording_hotkey_mode_changed mode=\(mode, privacy: .public)")
        }
    }

    private func loadCredentials() {
        do {
            tencentSecretId = try credentialStore.read(account: CredentialAccount.tencentSecretId) ?? ""
            tencentSecretKey = try credentialStore.read(account: CredentialAccount.tencentSecretKey) ?? ""
            llmAPIKey = try credentialStore.read(account: CredentialAccount.llmAPIKey) ?? ""
        } catch {
            saveMessage = "读取 Keychain 失败：\(error.localizedDescription)"
        }
    }

    private func saveTencentCredentials() {
        do {
            try credentialStore.save(tencentSecretId, account: CredentialAccount.tencentSecretId)
            try credentialStore.save(tencentSecretKey, account: CredentialAccount.tencentSecretKey)
            saveMessage = "腾讯云配置已保存"
        } catch {
            saveMessage = "保存腾讯云配置失败：\(error.localizedDescription)"
        }
    }

    private func saveLLMCredentials() {
        do {
            try credentialStore.save(llmAPIKey, account: CredentialAccount.llmAPIKey)
            saveMessage = "LLM 配置已保存"
        } catch {
            saveMessage = "保存 LLM 配置失败：\(error.localizedDescription)"
        }
    }

    private func chooseAudioStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: audioStorageDirectory, isDirectory: true)
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else {
            AppLog.capture.info("audio_storage_directory_selection_cancelled")
            return
        }

        audioStorageDirectory = url.path
        saveMessage = "录音目录已设置：\(url.path)"
        AppLog.capture.info("audio_storage_directory_selected directory=\(url.path, privacy: .public)")
    }

    private func openAudioStorageDirectory() {
        let url = URL(fileURLWithPath: audioStorageDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
            AppLog.capture.info("audio_storage_directory_opened directory=\(url.path, privacy: .public)")
        } catch {
            saveMessage = "打开录音目录失败：\(error.localizedDescription)"
            AppLog.capture.error("audio_storage_directory_open_failed directory=\(url.path, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func checkSTTConfiguration() {
        if sttProvider == "sensevoice" {
            Task {
                saveMessage = "正在检查 SenseVoice 本地环境..."
                do {
                    try await checkSenseVoiceEnvironment()
                    saveMessage = "SenseVoice 配置完整：路径、Python 与依赖均可用"
                } catch {
                    saveMessage = "SenseVoice 配置不可用：\(error.localizedDescription)"
                    AppLog.stt.error("sensevoice_environment_check_failed repoConfigured=\(!senseVoiceRepoPath.isEmpty, privacy: .public) pythonConfigured=\(!senseVoicePythonPath.isEmpty, privacy: .public) error=\(String(describing: error), privacy: .public)")
                }
            }
            return
        }

        let status = ConfigurationStatusProvider().currentStatus()
        saveMessage = status.sttConfigured ? "STT 配置完整" : sttConfigurationHint
    }

    private func testSTTConfiguration() {
        Task { @MainActor in
            isTestingSTT = true
            saveMessage = "请说一句 3 秒以内的测试语音..."

            let processId = UUID()
            let recorder = AudioRecorder()
            var audioURL: URL?

            do {
                let granted = await recorder.requestMicrophoneAccess()
                guard granted else {
                    saveMessage = "STT 测试失败：麦克风权限未开启"
                    AppLog.stt.error("stt_configuration_test_failed provider=\(sttProvider, privacy: .public) processId=\(processId.uuidString, privacy: .public) reason=microphone_denied")
                    isTestingSTT = false
                    return
                }

                audioURL = try recorder.start(processId: processId)
                try await Task.sleep(for: .seconds(3))
                recorder.stop(processId: processId)

                let service = try makeTestingTranscriptionService()
                let result = try await service.transcribe(
                    audioFile: audioURL,
                    context: TranscriptionContext(
                        processId: processId,
                        platform: "macOS",
                        localeIdentifier: Locale.current.identifier,
                        maxDurationSeconds: 3
                    )
                )

                saveMessage = "STT 测试成功：\(result.text)"
                AppLog.stt.info("stt_configuration_test_completed provider=\(result.provider, privacy: .public) processId=\(processId.uuidString, privacy: .public) transcriptLength=\(result.text.count, privacy: .public)")
            } catch {
                if let audioURL {
                    recorder.stop(processId: processId)
                    AppLog.stt.info("stt_configuration_test_recording_stopped_after_error processId=\(processId.uuidString, privacy: .public) audioFile=\(audioURL.lastPathComponent, privacy: .public)")
                }
                saveMessage = "STT 测试失败：\(error.localizedDescription)"
                AppLog.stt.error("stt_configuration_test_failed provider=\(sttProvider, privacy: .public) processId=\(processId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }

            isTestingSTT = false
        }
    }

    private func testLLMConfiguration() {
        Task {
            isTestingLLM = true
            defer { isTestingLLM = false }

            do {
                let apiKey = try credentialStore.read(account: CredentialAccount.llmAPIKey) ?? ""
                let service: TaskParsingService
                if llmProvider == "mock" {
                    service = MockTaskParsingService()
                } else {
                    service = OpenAICompatibleTaskParsingService(
                        baseURL: llmBaseURL,
                        apiKey: apiKey,
                        model: llmModel
                    )
                }

                let result = try await service.parse(
                    input: TaskParseInput(
                        text: "明天下午三点提醒我确认合同审批",
                        capturedAt: Date(),
                        timeZoneIdentifier: TimeZone.current.identifier,
                        localeIdentifier: Locale.current.identifier
                    )
                )
                saveMessage = "LLM 测试成功：\(result.title)"
            } catch {
                saveMessage = "LLM 测试失败：\(error.localizedDescription)"
                AppLog.aiParse.error("llm_configuration_test_failed provider=\(llmProvider, privacy: .public) model=\(llmModel, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func makeTestingTranscriptionService() throws -> SpeechTranscriptionService {
        if sttProvider == "mock" {
            return MockTranscriptionService()
        }

        if sttProvider == "sensevoice" {
            return SenseVoiceLocalTranscriptionService(
                repoPath: SenseVoiceDefaults.currentConfiguration().repoPath,
                pythonPath: SenseVoiceDefaults.currentConfiguration().pythonPath,
                modelName: SenseVoiceDefaults.currentConfiguration().modelName,
                device: SenseVoiceDefaults.currentConfiguration().device,
                language: senseVoiceLanguage,
                port: SenseVoiceDefaults.currentConfiguration().port
            )
        }

        let secretId = try credentialStore.read(account: CredentialAccount.tencentSecretId) ?? ""
        let secretKey = try credentialStore.read(account: CredentialAccount.tencentSecretKey) ?? ""
        guard !secretId.isEmpty, !secretKey.isEmpty else {
            AppLog.stt.error("stt_configuration_test_skipped provider=tencent reason=credential_missing")
            throw TranscriptionError.providerNotConfigured(provider: "tencent")
        }

        return TencentShortASRService(
            secretId: secretId,
            secretKey: secretKey,
            engine: tencentEngine
        )
    }

    private func checkSenseVoiceEnvironment() async throws {
        try await SenseVoiceServiceManager.shared.ensureRunning(configuration: SenseVoiceDefaults.currentConfiguration())
    }

    private func startSenseVoiceServiceIfSelected(reason: String, forceRestart: Bool = false) {
        guard sttProvider == "sensevoice" else { return }

        Task {
            saveMessage = "正在后台启动 SenseVoice 服务..."
            do {
                if forceRestart {
                    await SenseVoiceServiceManager.shared.stop(reason: reason)
                }

                try await SenseVoiceServiceManager.shared.ensureRunning(
                    configuration: SenseVoiceDefaults.currentConfiguration()
                )
                saveMessage = "SenseVoice 服务已就绪：127.0.0.1:\(SenseVoiceDefaults.currentConfiguration().port)"
                AppLog.stt.info("sensevoice_service_start_requested surface=settings reason=\(reason, privacy: .public) forceRestart=\(forceRestart, privacy: .public) port=\(SenseVoiceDefaults.currentConfiguration().port, privacy: .public)")
            } catch {
                saveMessage = "SenseVoice 服务启动失败：\(error.localizedDescription)"
                AppLog.stt.error("sensevoice_service_start_failed surface=settings reason=\(reason, privacy: .public) forceRestart=\(forceRestart, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func migrateSenseVoicePathsIfNeeded() {
        let configuredRepoPath = senseVoiceRepoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredRepoPath.isEmpty || !FileManager.default.fileExists(atPath: configuredRepoPath) {
            senseVoiceRepoPath = SenseVoiceDefaults.repoPath
            AppLog.stt.info("sensevoice_repo_path_migrated path=\(senseVoiceRepoPath, privacy: .public)")
        }

        let configuredPythonPath = senseVoicePythonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredPythonPath.isEmpty || configuredPythonPath == "/usr/bin/python3" || !FileManager.default.isExecutableFile(atPath: configuredPythonPath) {
            senseVoicePythonPath = SenseVoiceDefaults.pythonPath
            AppLog.stt.info("sensevoice_python_path_migrated path=\(senseVoicePythonPath, privacy: .public)")
        }
    }

    private var sttHelpText: String {
        switch sttProvider {
        case "sensevoice":
            "本地 SenseVoice 随 App 打包源码，不上传音频。首次使用会在用户目录创建私有 Python 环境并安装依赖，模型可能按需下载。"
        case "mock":
            "Mock 不会调用真实 STT，只用于调试录入和解析流程。"
        default:
            "默认引擎 16k_zh-PY，适合普通话短语音。录音文件会直连腾讯云一句话识别。"
        }
    }

    private var sttConfigurationHint: String {
        switch sttProvider {
        case "sensevoice":
            "STT 配置不完整：请确认系统可用 python3，或设置 MINDANCHOR_BOOTSTRAP_PYTHON 指向可执行 Python。"
        case "mock":
            "STT 配置完整"
        default:
            "STT 配置不完整：请填写腾讯云 SecretId/SecretKey，或切换到 Mock / 本地 SenseVoice"
        }
    }
}
