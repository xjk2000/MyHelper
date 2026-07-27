import Foundation
import Observation

@Observable
final class SettingsStore {
    private(set) var config: AppConfig
    private let configFile: ConfigFile
    private let keychain: KeychainHelper

    /// 当前选中的实例 id(UI 用),持久化暂不需要
    var currentInstanceId: UUID?

    init(configFile: ConfigFile = ConfigFile(),
         keychain: KeychainHelper = KeychainHelper()) throws {
        self.configFile = configFile
        self.keychain = keychain
        self.config = try configFile.load()
        self.currentInstanceId = config.instances.first?.id
    }

    // MARK: - Instance CRUD

    func addInstance(_ instance: GitLabInstance, token: String) throws {
        config.instances.append(instance)
        try keychain.set(token, for: instance.id.uuidString)
        try saveConfig()
        if currentInstanceId == nil { currentInstanceId = instance.id }
    }

    func updateInstance(_ instance: GitLabInstance, token: String?) throws {
        guard let idx = config.instances.firstIndex(where: { $0.id == instance.id }) else {
            return
        }
        config.instances[idx] = instance
        if let token { try keychain.set(token, for: instance.id.uuidString) }
        try saveConfig()
    }

    func removeInstance(id: UUID) throws {
        config.instances.removeAll { $0.id == id }
        config.monitor.targets.removeAll { $0.instanceId == id }
        try keychain.remove(id.uuidString)
        try saveConfig()
        if currentInstanceId == id { currentInstanceId = config.instances.first?.id }
    }

    // MARK: - Clone Settings

    func updateCloneSettings(_ s: CloneSettings) throws {
        config.clone = s
        try saveConfig()
    }

    // MARK: - Monitor Settings

    func updateMonitorSettings(_ s: MonitorSettings) throws {
        config.monitor = s
        try saveConfig()
    }

    func upsertMonitorTarget(project: GLProject, branch: String) throws {
        config.monitor.upsert(project: project, branch: branch)
        try saveConfig()
    }

    func upsertMonitorTarget(project: GLProject, branches: [String]) throws {
        config.monitor.upsert(project: project, branches: branches)
        try saveConfig()
    }

    func upsertMonitorTarget(project: GLProject, watches: [MonitorBranchWatch]) throws {
        config.monitor.upsert(project: project, watches: watches)
        try saveConfig()
    }

    func updateMonitorTarget(_ target: MonitorTarget) throws {
        guard let index = config.monitor.targets.firstIndex(where: { $0.id == target.id }) else {
            return
        }
        if target.watches.isEmpty {
            config.monitor.targets.remove(at: index)
            try saveConfig()
            return
        }
        config.monitor.targets[index] = target
        try saveConfig()
    }

    func removeMonitorTarget(id: String) throws {
        config.monitor.targets.removeAll { $0.id == id }
        try saveConfig()
    }

    // MARK: - Token access

    func token(for instanceId: UUID) -> String? {
        try? keychain.get(instanceId.uuidString)
    }

    // MARK: - Helpers

    private func saveConfig() throws {
        try configFile.save(config)
    }
}
