import Foundation

enum ModelRadarStatus: String, Equatable {
    case green
    case yellow
    case red
    case unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "green": self = .green
        case "yellow": self = .yellow
        case "red": self = .red
        default: self = .unknown
        }
    }
}

struct ModelRadarReading: Equatable {
    let key: String
    let label: String
    let date: String
    let score: Double
    let status: ModelRadarStatus
    let passed: Int
    let tasks: Int
    let wallTimeHuman: String?
    let costUSD: Double?
}

struct ModelRadarSnapshot: Equatable {
    let updatedAt: Date?
    let latest: ModelRadarReading
    let recentReadings: [ModelRadarReading]
    let modelReadings: [ModelRadarReading]
    let attribution: String
    let sourceURL: URL
}

enum ModelRadarServiceError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingModelIQ

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "雷达站返回了无效响应"
        case let .httpStatus(statusCode):
            return "雷达数据请求失败（HTTP \(statusCode)）"
        case .missingModelIQ:
            return "公开数据中暂时没有降智雷达结果"
        }
    }
}

struct ModelRadarService {
    static let codexSourceURL = URL(string: "https://codexradar.com/")!
    static let claudeCodeSourceURL = URL(string: "https://claudecoderadar.com/")!
    private static let codexEndpoint = URL(string: "https://codexradar.com/current.json")!
    private static let claudeCodeEndpoint = URL(string: "https://claudecoderadar.com/data/claude-code-radar.json")!

    func load(for scope: RuntimeScope) async throws -> ModelRadarSnapshot {
        switch scope {
        case .codex:
            return try await loadCodexRadar()
        case .claudeCode:
            return try await loadClaudeCodeRadar()
        }
    }

    static func sourceURL(for scope: RuntimeScope) -> URL {
        switch scope {
        case .codex:
            return codexSourceURL
        case .claudeCode:
            return claudeCodeSourceURL
        }
    }

    private func loadCodexRadar() async throws -> ModelRadarSnapshot {
        var request = URLRequest(
            url: Self.codexEndpoint,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyHelper/1.0 (+https://codexradar.com/)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelRadarServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelRadarServiceError.httpStatus(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(CodexRadarPayload.self, from: data)
        guard let modelIQ = payload.modelIQ,
              let latestDTO = modelIQ.latest,
              let primary = reading(
                key: "gpt_56_sol_max",
                fallbackLabel: "GPT-5.6 Sol max",
                dto: latestDTO
              ) else {
            throw ModelRadarServiceError.missingModelIQ
        }

        let recentReadings = modelIQ.recentDays.compactMap { dto in
            reading(key: "gpt_56_sol_max", fallbackLabel: primary.label, dto: dto)
        }

        let comparisonOrder = [
            "gpt_56_sol_xhigh",
            "gpt_56_sol_high",
            "gpt_56_sol_medium",
            "gpt_56_sol_low",
            "gpt_56_terra_max",
            "gpt_56_terra_medium",
            "gpt_56_luna_max",
            "gpt_56_luna_medium"
        ]
        let comparisons = comparisonOrder.compactMap { key -> ModelRadarReading? in
            guard let comparison = modelIQ.comparisons[key], let latest = comparison.latest else {
                return nil
            }
            return reading(key: key, fallbackLabel: comparison.label ?? key, dto: latest)
        }

        let attribution = payload.apiAccess?.requirements?.attributionText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let siteURL = payload.apiAccess?.requirements?.site.flatMap(URL.init(string:))

        return ModelRadarSnapshot(
            updatedAt: parseISO8601(modelIQ.quotaRadar?.updatedAt ?? payload.monitoredAt),
            latest: primary,
            recentReadings: recentReadings,
            modelReadings: [primary] + comparisons,
            attribution: attribution?.isEmpty == false
                ? attribution!
                : "数据来自 Codex 雷达 codexradar.com",
            sourceURL: siteURL ?? Self.codexSourceURL
        )
    }

    private func loadClaudeCodeRadar() async throws -> ModelRadarSnapshot {
        var request = URLRequest(
            url: Self.claudeCodeEndpoint,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyHelper/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelRadarServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelRadarServiceError.httpStatus(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(ClaudeCodeRadarPayload.self, from: data)
        guard let iq = payload.iq else {
            throw ModelRadarServiceError.missingModelIQ
        }

        let modelReadings = iq.models.compactMap { model in
            claudeCodeLatestReading(model: model, labels: payload.labels)
        }
        guard !modelReadings.isEmpty else {
            throw ModelRadarServiceError.missingModelIQ
        }

        let primaryModel = iq.models.max { lhs, rhs in
            let left = parseISO8601(lhs.latestAt) ?? .distantPast
            let right = parseISO8601(rhs.latestAt) ?? .distantPast
            return left < right
        }
        let primary = primaryModel
            .flatMap { claudeCodeLatestReading(model: $0, labels: payload.labels) }
            ?? modelReadings[0]
        let recentReadings = primaryModel.map {
            claudeCodeHistory(model: $0, labels: payload.labels)
        } ?? [primary]

        return ModelRadarSnapshot(
            updatedAt: parseISO8601(iq.updatedAt ?? payload.updatedAt),
            latest: primary,
            recentReadings: recentReadings,
            modelReadings: modelReadings,
            attribution: "数据来自 Claude Code 雷达 claudecoderadar.com",
            sourceURL: Self.claudeCodeSourceURL
        )
    }

    private func claudeCodeLatestReading(
        model: ClaudeCodeRadarModelDTO,
        labels: [String]
    ) -> ModelRadarReading? {
        guard let index = model.iq.lastIndex(where: { $0 != nil }),
              let score = model.iq[index] else {
            return nil
        }

        return ModelRadarReading(
            key: model.key,
            label: model.name,
            date: model.latestLabel ?? element(in: labels, at: index) ?? "",
            score: score,
            status: status(for: score),
            passed: optionalElement(in: model.pass, at: index) ?? 0,
            tasks: optionalElement(in: model.valid, at: index) ?? 0,
            wallTimeHuman: optionalElement(in: model.time, at: index).map { String(format: "%.1fh", $0) },
            costUSD: optionalElement(in: model.cost, at: index)
        )
    }

    private func claudeCodeHistory(
        model: ClaudeCodeRadarModelDTO,
        labels: [String]
    ) -> [ModelRadarReading] {
        model.iq.indices.compactMap { index -> ModelRadarReading? in
            guard let score = model.iq[index] else { return nil }
            return ModelRadarReading(
                key: model.key,
                label: model.name,
                date: element(in: labels, at: index) ?? model.latestLabel ?? "",
                score: score,
                status: status(for: score),
                passed: optionalElement(in: model.pass, at: index) ?? 0,
                tasks: optionalElement(in: model.valid, at: index) ?? 0,
                wallTimeHuman: optionalElement(in: model.time, at: index).map { String(format: "%.1fh", $0) },
                costUSD: optionalElement(in: model.cost, at: index)
            )
        }
    }

    private func status(for score: Double) -> ModelRadarStatus {
        if score >= 105 { return .green }
        if score >= 90 { return .yellow }
        return .red
    }

    private func element<T>(in values: [T], at index: Int) -> T? {
        guard values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func optionalElement<T>(in values: [T?], at index: Int) -> T? {
        guard values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func reading(
        key: String,
        fallbackLabel: String,
        dto: CodexRadarReadingDTO
    ) -> ModelRadarReading? {
        guard let score = dto.score else { return nil }
        return ModelRadarReading(
            key: key,
            label: fallbackLabel,
            date: dto.date ?? "",
            score: score,
            status: ModelRadarStatus(rawValue: dto.status),
            passed: dto.passed ?? 0,
            tasks: dto.tasks ?? 0,
            wallTimeHuman: dto.wallTimeHuman,
            costUSD: dto.costUSD
        )
    }

    private func parseISO8601(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

private struct ClaudeCodeRadarPayload: Decodable {
    let updatedAt: String?
    let labels: [String]
    let iq: ClaudeCodeRadarIQDTO?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case labels
        case iq
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        iq = try container.decodeIfPresent(ClaudeCodeRadarIQDTO.self, forKey: .iq)
    }
}

private struct ClaudeCodeRadarIQDTO: Decodable {
    let updatedAt: String?
    let models: [ClaudeCodeRadarModelDTO]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        models = try container.decodeIfPresent([ClaudeCodeRadarModelDTO].self, forKey: .models) ?? []
    }
}

private struct ClaudeCodeRadarModelDTO: Decodable {
    let key: String
    let name: String
    let iq: [Double?]
    let pass: [Int?]
    let valid: [Int?]
    let cost: [Double?]
    let time: [Double?]
    let latestAt: String?
    let latestLabel: String?

    enum CodingKeys: String, CodingKey {
        case key
        case name
        case iq
        case pass
        case valid
        case cost
        case time
        case latestAt = "latest_at"
        case latestLabel = "latest_label"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        iq = try container.decodeIfPresent([Double?].self, forKey: .iq) ?? []
        pass = try container.decodeIfPresent([Int?].self, forKey: .pass) ?? []
        valid = try container.decodeIfPresent([Int?].self, forKey: .valid) ?? []
        cost = try container.decodeIfPresent([Double?].self, forKey: .cost) ?? []
        time = try container.decodeIfPresent([Double?].self, forKey: .time) ?? []
        latestAt = try container.decodeIfPresent(String.self, forKey: .latestAt)
        latestLabel = try container.decodeIfPresent(String.self, forKey: .latestLabel)
    }
}

private struct CodexRadarPayload: Decodable {
    let monitoredAt: String?
    let apiAccess: CodexRadarAPIAccessDTO?
    let modelIQ: CodexRadarModelIQDTO?

    enum CodingKeys: String, CodingKey {
        case monitoredAt = "monitored_at"
        case apiAccess = "api_access"
        case modelIQ = "model_iq"
    }
}

private struct CodexRadarAPIAccessDTO: Decodable {
    let requirements: CodexRadarRequirementsDTO?
}

private struct CodexRadarRequirementsDTO: Decodable {
    let attributionText: String?
    let site: String?

    enum CodingKeys: String, CodingKey {
        case attributionText = "attribution_text"
        case site
    }
}

private struct CodexRadarModelIQDTO: Decodable {
    let latest: CodexRadarReadingDTO?
    let recentDays: [CodexRadarReadingDTO]
    let comparisons: [String: CodexRadarComparisonDTO]
    let quotaRadar: CodexRadarQuotaRadarDTO?

    enum CodingKeys: String, CodingKey {
        case latest
        case recentDays = "recent_days"
        case comparisons
        case quotaRadar = "quota_radar"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(CodexRadarReadingDTO.self, forKey: .latest)
        recentDays = try container.decodeIfPresent([CodexRadarReadingDTO].self, forKey: .recentDays) ?? []
        comparisons = try container.decodeIfPresent([String: CodexRadarComparisonDTO].self, forKey: .comparisons) ?? [:]
        quotaRadar = try container.decodeIfPresent(CodexRadarQuotaRadarDTO.self, forKey: .quotaRadar)
    }
}

private struct CodexRadarComparisonDTO: Decodable {
    let label: String?
    let latest: CodexRadarReadingDTO?
}

private struct CodexRadarQuotaRadarDTO: Decodable {
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
}

private struct CodexRadarReadingDTO: Decodable {
    let date: String?
    let score: Double?
    let status: String?
    let passed: Int?
    let tasks: Int?
    let wallTimeHuman: String?
    let costUSD: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case score
        case status
        case passed
        case tasks
        case wallTimeHuman = "wall_time_human"
        case costUSD = "cost_usd"
    }
}
