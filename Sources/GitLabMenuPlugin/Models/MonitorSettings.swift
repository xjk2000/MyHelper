import Foundation

struct MonitorTarget: Identifiable, Codable, Equatable, Hashable {
    var id: String { "\(instanceId.uuidString):\(projectId)" }
    var instanceId: UUID
    var projectId: Int
    var name: String
    var pathWithNamespace: String
    var watches: [MonitorBranchWatch]

    var branch: String {
        get { normalizedBranches.first ?? "main" }
        set { watches = [MonitorBranchWatch(selector: .fixed(newValue), role: .production)] }
    }

    var branches: [String] {
        get { normalizedBranches }
        set {
            watches = Self.watches(from: newValue, fallback: "main")
        }
    }

    var normalizedBranches: [String] {
        watches.map { watch in
            switch watch.selector {
            case .fixed(let branch):
                return branch.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return watch.selector.displayHint
            }
        }
        .filter { !$0.isEmpty }
    }

    var productionWatch: MonitorBranchWatch? {
        watches.first { $0.role == .production }
    }

    var testingWatch: MonitorBranchWatch? {
        watches.first { $0.role == .testing }
    }

    var roleSummary: String {
        watches
            .compactMap { watch -> String? in
                let hint = watch.selector.displayHint.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hint.isEmpty else { return nil }
                return "\(watch.role.displayName): \(watch.roleSummary)"
            }
            .joined(separator: "\n")
    }

    init(instanceId: UUID, projectId: Int, name: String,
         pathWithNamespace: String, branch: String) {
        self.init(
            instanceId: instanceId,
            projectId: projectId,
            name: name,
            pathWithNamespace: pathWithNamespace,
            branches: [branch]
        )
    }

    init(instanceId: UUID, projectId: Int, name: String,
         pathWithNamespace: String, branches: [String]) {
        self.instanceId = instanceId
        self.projectId = projectId
        self.name = name
        self.pathWithNamespace = pathWithNamespace
        self.watches = Self.watches(from: branches, fallback: "main")
    }

    init(instanceId: UUID, projectId: Int, name: String,
         pathWithNamespace: String, watches: [MonitorBranchWatch]) {
        self.instanceId = instanceId
        self.projectId = projectId
        self.name = name
        self.pathWithNamespace = pathWithNamespace
        self.watches = watches.isEmpty
            ? [MonitorBranchWatch(selector: .fixed("main"), role: .production)]
            : watches
    }

    func statusId(for branch: String) -> String {
        "\(id):\(branch)"
    }

    func statusId(for watch: MonitorBranchWatch) -> String {
        "\(id):\(watch.id.uuidString)"
    }

    private enum CodingKeys: String, CodingKey {
        case instanceId
        case projectId
        case name
        case pathWithNamespace
        case branch
        case branches
        case watches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instanceId = try container.decode(UUID.self, forKey: .instanceId)
        projectId = try container.decode(Int.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        pathWithNamespace = try container.decode(String.self, forKey: .pathWithNamespace)
        if let decodedWatches = try container.decodeIfPresent([MonitorBranchWatch].self, forKey: .watches),
           !decodedWatches.isEmpty {
            watches = decodedWatches
        } else {
            let decodedBranches = try container.decodeIfPresent([String].self, forKey: .branches)
            let legacyBranch = try container.decodeIfPresent(String.self, forKey: .branch)
            watches = Self.watches(from: decodedBranches ?? [legacyBranch ?? "main"], fallback: "main")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(instanceId, forKey: .instanceId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(name, forKey: .name)
        try container.encode(pathWithNamespace, forKey: .pathWithNamespace)
        try container.encode(watches, forKey: .watches)
        try container.encode(normalizedBranches, forKey: .branches)
        try container.encode(branch, forKey: .branch)
    }

    static func normalizedBranches(_ branches: [String], fallback: String) -> [String] {
        let trimmed = branches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = trimmed.filter { seen.insert($0).inserted }
        if !unique.isEmpty { return unique }
        let fallbackBranch = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackBranch.isEmpty ? ["main"] : [fallbackBranch]
    }

    static func watches(from branches: [String], fallback: String) -> [MonitorBranchWatch] {
        normalizedBranches(branches, fallback: fallback).enumerated().map { index, branch in
            let role: MonitorBranchRole
            switch index {
            case 0: role = .production
            case 1: role = .testing
            default: role = .custom
            }
            return MonitorBranchWatch(selector: .fixed(branch), role: role)
        }
    }
}

struct MonitorSettings: Codable, Equatable {
    var pollIntervalSeconds: Int = 60
    var targets: [MonitorTarget] = []

    func target(for project: GLProject) -> MonitorTarget? {
        targets.first {
            $0.instanceId == project.instanceId && $0.projectId == project.id
        }
    }

    func productionWatch(for project: GLProject) -> MonitorBranchWatch? {
        target(for: project)?.productionWatch
    }

    mutating func upsert(project: GLProject, branch: String) {
        upsert(project: project, branches: [branch])
    }

    mutating func upsert(project: GLProject, branches: [String]) {
        let normalizedBranches = MonitorTarget.normalizedBranches(
            branches,
            fallback: project.defaultBranch ?? "main"
        )
        upsert(
            project: project,
            watches: MonitorTarget.watches(from: normalizedBranches, fallback: project.defaultBranch ?? "main")
        )
    }

    mutating func upsert(project: GLProject, watches: [MonitorBranchWatch]) {
        let target = MonitorTarget(
            instanceId: project.instanceId,
            projectId: project.id,
            name: project.name,
            pathWithNamespace: project.pathWithNamespace,
            watches: watches
        )
        if let index = targets.firstIndex(where: {
            $0.instanceId == project.instanceId && $0.projectId == project.id
        }) {
            targets[index] = target
        } else {
            targets.append(target)
        }
    }
}
