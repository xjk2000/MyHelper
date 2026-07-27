import Foundation

struct ConfigurationStatus {
    let sttConfigured: Bool
    let llmConfigured: Bool

    var hasBlockingIssue: Bool {
        !llmConfigured
    }
}

struct ConfigurationStatusProvider {
    private let credentialStore = SecureCredentialStore()

    func currentStatus() -> ConfigurationStatus {
        let sttProvider = UserDefaults.standard.string(forKey: AppSettingKey.sttProvider) ?? "tencent"
        let llmProvider = UserDefaults.standard.string(forKey: AppSettingKey.llmProvider) ?? "openaiCompatible"

        let sttConfigured: Bool
        if sttProvider == "mock" {
            sttConfigured = true
        } else if sttProvider == "sensevoice" {
            let repoPath = UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceRepoPath) ?? SenseVoiceDefaults.repoPath
            let pythonPath = UserDefaults.standard.string(forKey: AppSettingKey.senseVoicePythonPath) ?? SenseVoiceDefaults.pythonPath
            sttConfigured = FileManager.default.fileExists(atPath: repoPath)
                && FileManager.default.isExecutableFile(atPath: pythonPath)
        } else {
            sttConfigured = hasCredential(CredentialAccount.tencentSecretId)
                && hasCredential(CredentialAccount.tencentSecretKey)
        }

        let llmConfigured: Bool
        if llmProvider == "mock" {
            llmConfigured = true
        } else {
            let baseURL = UserDefaults.standard.string(forKey: AppSettingKey.llmBaseURL) ?? ""
            let model = UserDefaults.standard.string(forKey: AppSettingKey.llmModel) ?? ""
            llmConfigured = !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && hasCredential(CredentialAccount.llmAPIKey)
        }

        AppLog.app.info("configuration_status_checked sttConfigured=\(sttConfigured, privacy: .public) llmConfigured=\(llmConfigured, privacy: .public)")
        return ConfigurationStatus(sttConfigured: sttConfigured, llmConfigured: llmConfigured)
    }

    private func hasCredential(_ account: String) -> Bool {
        do {
            return try credentialStore.read(account: account)?.isEmpty == false
        } catch {
            AppLog.security.error("configuration_credential_check_failed account=\(account, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return false
        }
    }
}
