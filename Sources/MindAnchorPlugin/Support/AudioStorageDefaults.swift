import Foundation

enum AudioStorageDefaults {
    static var directoryPath: String {
        LocalTaskStore.projectRootURL()
            .appendingPathComponent(LocalTaskStore.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
            .path
    }

    static var currentDirectoryPath: String {
        let configured = UserDefaults.standard.string(forKey: AppSettingKey.audioStorageDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? directoryPath : configured
    }
}
