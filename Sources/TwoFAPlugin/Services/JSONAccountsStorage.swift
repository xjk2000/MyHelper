import Foundation

final class JSONAccountsStorage {
    enum StorageError: LocalizedError {
        case cannotCreateApplicationSupportDirectory

        var errorDescription: String? {
            switch self {
            case .cannotCreateApplicationSupportDirectory:
                return "无法创建应用数据目录"
            }
        }
    }

    private let filePathKey = "TwoFAPlugin.accountsJSONFilePath"
    private let legacyFilePathKey = "accountsJSONFilePath"
    private let userDefaults: UserDefaults
    private let defaultURLOverride: URL?

    init(userDefaults: UserDefaults = .standard, defaultURL: URL? = nil) {
        self.userDefaults = userDefaults
        self.defaultURLOverride = defaultURL
    }

    var fileURL: URL {
        if let path = userDefaults.string(forKey: filePathKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        if let path = userDefaults.string(forKey: legacyFilePathKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return defaultFileURL
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    var legacyTwoFAToolFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directoryURL = (baseURL ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("TwoFATool", isDirectory: true)
        return directoryURL.appendingPathComponent("accounts.json")
    }

    var legacyTwoFAToolFileExists: Bool {
        FileManager.default.fileExists(atPath: legacyTwoFAToolFileURL.path)
    }

    func load() throws -> [TOTPAccount] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TOTPAccount].self, from: data)
    }

    func save(_ accounts: [TOTPAccount]) throws {
        let url = fileURL
        try write(accounts, to: url)
    }

    func moveStorage(to url: URL, accounts: [TOTPAccount]) throws {
        let normalizedURL = url.pathExtension.lowercased() == "json"
            ? url
            : url.appendingPathExtension("json")

        try write(accounts, to: normalizedURL)
        persistFileURL(normalizedURL)
    }

    func useExistingStorage(at url: URL) throws -> [TOTPAccount] {
        let accounts = try load(from: url)
        persistFileURL(url)
        return accounts
    }

    func accountCount(in url: URL) throws -> Int {
        try load(from: url).count
    }

    private func load(from url: URL) throws -> [TOTPAccount] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TOTPAccount].self, from: data)
    }

    private func persistFileURL(_ url: URL) {
        userDefaults.set(url.path, forKey: filePathKey)
        userDefaults.removeObject(forKey: legacyFilePathKey)
    }

    private var defaultFileURL: URL {
        if let defaultURLOverride {
            return defaultURLOverride
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directoryURL = (baseURL ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("MyHelper", isDirectory: true)
            .appendingPathComponent("TwoFA", isDirectory: true)
        return directoryURL.appendingPathComponent("accounts.json")
    }

    private func write(_ accounts: [TOTPAccount], to url: URL) throws {
        guard let directoryURL = url.deletingLastPathComponentIfPossible else {
            throw StorageError.cannotCreateApplicationSupportDirectory
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(accounts)
        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if FileManager.default.fileExists(atPath: url.path) {
            try backupExistingFileIfNeeded(at: url)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    private func backupExistingFileIfNeeded(at url: URL) throws {
        let backupURL = url.appendingPathExtension("bak")

        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }

        try FileManager.default.copyItem(at: url, to: backupURL)
    }
}

private extension URL {
    var deletingLastPathComponentIfPossible: URL? {
        let directoryURL = deletingLastPathComponent()
        return directoryURL.path.isEmpty ? nil : directoryURL
    }
}
