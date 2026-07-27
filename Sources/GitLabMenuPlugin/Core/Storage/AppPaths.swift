import Foundation

enum AppPaths {
    static let appName = "GitLabMenu"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base
            .appendingPathComponent("MyHelper", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    static var legacySupportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var configFileURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    static var legacyConfigFileURL: URL {
        legacySupportDirectory.appendingPathComponent("config.json")
    }

    static var monitorCursorsURL: URL {
        // 下一份 plan 才用到,这里先声明位置
        supportDirectory.appendingPathComponent("monitor-cursors.json")
    }

    static func ensureSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true
        )
        try migrateLegacyConfigIfNeeded()
    }

    private static func migrateLegacyConfigIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: configFileURL.path),
              FileManager.default.fileExists(atPath: legacyConfigFileURL.path)
        else { return }

        try FileManager.default.copyItem(at: legacyConfigFileURL, to: configFileURL)
    }
}
