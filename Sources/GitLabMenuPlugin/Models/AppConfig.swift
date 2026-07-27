import Foundation

struct AppConfig: Codable, Equatable {
    var instances: [GitLabInstance]
    var clone: CloneSettings
    var monitor: MonitorSettings

    static let defaultEmpty = AppConfig(
        instances: [],
        clone: CloneSettings(),
        monitor: MonitorSettings()
    )

    init(instances: [GitLabInstance],
         clone: CloneSettings,
         monitor: MonitorSettings = MonitorSettings()) {
        self.instances = instances
        self.clone = clone
        self.monitor = monitor
    }

    private enum CodingKeys: String, CodingKey {
        case instances
        case clone
        case monitor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instances = try container.decodeIfPresent([GitLabInstance].self, forKey: .instances) ?? []
        clone = try container.decodeIfPresent(CloneSettings.self, forKey: .clone) ?? CloneSettings()
        monitor = try container.decodeIfPresent(MonitorSettings.self, forKey: .monitor) ?? MonitorSettings()
    }
}
