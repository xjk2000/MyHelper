import Foundation

enum AppSettingKey {
    static let sttProvider = "sttProvider"
    static let tencentEngine = "tencentEngine"
    static let senseVoiceRepoPath = "senseVoiceRepoPath"
    static let senseVoicePythonPath = "senseVoicePythonPath"
    static let senseVoiceModel = "senseVoiceModel"
    static let senseVoiceDevice = "senseVoiceDevice"
    static let senseVoiceLanguage = "senseVoiceLanguage"
    static let senseVoicePort = "senseVoicePort"
    static let llmProvider = "llmProvider"
    static let llmBaseURL = "llmBaseURL"
    static let llmModel = "llmModel"
    static let defaultReminderOffsetMinutes = "defaultReminderOffsetMinutes"
    static let audioStorageDirectory = "audioStorageDirectory"
    static let maximumRecordingSeconds = "maximumRecordingSeconds"
    static let recordingHotkeyMode = "recordingHotkeyMode"
}

enum CredentialAccount {
    static let tencentSecretId = "tencentSecretId"
    static let tencentSecretKey = "tencentSecretKey"
    static let llmAPIKey = "llmAPIKey"
}

enum RecordingSettings {
    static let defaultMaximumSeconds = 60
    static let minimumMaximumSeconds = 5
    static let maximumMaximumSeconds = 600

    static var maximumRecordingSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettingKey.maximumRecordingSeconds)
        let value = stored == 0 ? defaultMaximumSeconds : stored
        return min(max(value, minimumMaximumSeconds), maximumMaximumSeconds)
    }
}

enum RecordingHotkeyMode: String, CaseIterable, Identifiable {
    case none
    case holdOption
    case optionSpace
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "无快捷键"
        case .holdOption: "长按 Option 录音"
        case .optionSpace: "Option + Space 按住录音"
        case .both: "长按 Option 与 Option + Space"
        }
    }

    var enablesHoldOption: Bool {
        self == .holdOption || self == .both
    }

    var enablesOptionSpace: Bool {
        self == .optionSpace || self == .both
    }

    static var current: RecordingHotkeyMode {
        let rawValue = UserDefaults.standard.string(forKey: AppSettingKey.recordingHotkeyMode) ?? RecordingHotkeyMode.none.rawValue
        return RecordingHotkeyMode(rawValue: rawValue) ?? .none
    }
}
