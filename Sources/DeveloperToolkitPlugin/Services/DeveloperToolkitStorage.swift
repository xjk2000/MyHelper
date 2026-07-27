import AppKit
import Foundation

enum DeveloperToolkitStorage {
    private static let storageDirectoryKey = "DeveloperToolkit.storageDirectory"

    static var storageDirectory: URL? {
        guard let path = UserDefaults.standard.string(forKey: storageDirectoryKey),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @MainActor
    @discardableResult
    static func chooseStorageDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择研发工具包存储目录"
        panel.message = "当前 JSON 会保存到该目录下的 JSON 文件夹。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = storageDirectory

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return nil
        }

        UserDefaults.standard.set(url.path, forKey: storageDirectoryKey)
        return url
    }

    @MainActor
    static func saveCurrentJSON(_ text: String) throws -> URL? {
        let rootDirectory = storageDirectory ?? chooseStorageDirectory()
        guard let rootDirectory else { return nil }

        let jsonDirectory = rootDirectory.appendingPathComponent("JSON", isDirectory: true)
        try FileManager.default.createDirectory(
            at: jsonDirectory,
            withIntermediateDirectories: true
        )

        let fileURL = nextAvailableJSONURL(in: jsonDirectory)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func nextAvailableJSONURL(in directory: URL) -> URL {
        let baseName = "json-\(filenameDateFormatter.string(from: Date()))"
        var candidate = directory.appendingPathComponent("\(baseName).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
