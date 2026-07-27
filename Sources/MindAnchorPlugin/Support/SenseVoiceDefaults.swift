import Foundation

enum SenseVoiceDefaults {
    static let developmentRepoPath = "/Volumes/ORICO/Projects/otherProjects/SenseVoice"
    static let developmentPythonPath = "/Volumes/ORICO/Projects/otherProjects/SenseVoice/.venv/bin/python"
    static let model = "iic/SenseVoiceSmall"
    static let device = "cpu"
    static let language = "auto"
    static let port = 50000

    static var repoPath: String {
        if let bundled = bundledRepoURL, FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }

        let projectResourcePath = LocalTaskStore.projectRootURL()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("SenseVoice", isDirectory: true)
            .path
        if FileManager.default.fileExists(atPath: projectResourcePath) {
            return projectResourcePath
        }

        return developmentRepoPath
    }

    static var pythonPath: String {
        managedPythonURL.path
    }

    static func currentConfiguration() -> SenseVoiceServiceConfiguration {
        let configuredRepoPath = UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceRepoPath)
        let configuredPythonPath = UserDefaults.standard.string(forKey: AppSettingKey.senseVoicePythonPath)
        let resolvedRepoPath = resolveExistingPath(configuredRepoPath, fallback: repoPath)
        let resolvedPythonPath = resolveExecutablePath(configuredPythonPath, fallback: pythonPath)

        return SenseVoiceServiceConfiguration(
            repoPath: resolvedRepoPath,
            pythonPath: resolvedPythonPath,
            modelName: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceModel) ?? model,
            device: UserDefaults.standard.string(forKey: AppSettingKey.senseVoiceDevice) ?? device,
            port: UserDefaults.standard.integer(forKey: AppSettingKey.senseVoicePort) == 0
                ? port
                : UserDefaults.standard.integer(forKey: AppSettingKey.senseVoicePort)
        )
    }

    static var bundledRepoURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("SenseVoice", isDirectory: true)
    }

    static var managedRuntimeDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MyHelper", isDirectory: true)
            .appendingPathComponent("MindAnchor", isDirectory: true)
            .appendingPathComponent("SenseVoiceRuntime", isDirectory: true)
    }

    static var managedPythonURL: URL {
        managedRuntimeDirectoryURL
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    private static func resolveExistingPath(_ configured: String?, fallback: String) -> String {
        guard let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty else {
            return fallback
        }
        return FileManager.default.fileExists(atPath: configured) ? configured : fallback
    }

    private static func resolveExecutablePath(_ configured: String?, fallback: String) -> String {
        guard let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty else {
            return fallback
        }
        return FileManager.default.isExecutableFile(atPath: configured) ? configured : fallback
    }
}
