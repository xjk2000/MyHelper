import Foundation

enum BranchDateFormat: String, Codable, CaseIterable, Hashable {
    case yyyymmdd
    case yyyymmddDashed
    case yyyymmddDotted
    case yyyymmddWithTail

    var displayName: String {
        switch self {
        case .yyyymmdd: return "YYYYMMDD"
        case .yyyymmddDashed: return "YYYY-MM-DD"
        case .yyyymmddDotted: return "YYYY.MM.DD"
        case .yyyymmddWithTail: return "YYYYMMDD-尾缀"
        }
    }

    func regex(prefix: String, separator: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        let escapedSeparator = NSRegularExpression.escapedPattern(for: separator)
        let head = "\(escaped)\(escapedSeparator)"
        switch self {
        case .yyyymmdd:
            return "^\(head)\\d{8}$"
        case .yyyymmddDashed:
            return "^\(head)\\d{4}-\\d{2}-\\d{2}$"
        case .yyyymmddDotted:
            return "^\(head)\\d{4}\\.\\d{2}\\.\\d{2}$"
        case .yyyymmddWithTail:
            return "^\(head)\\d{8}-.+$"
        }
    }
}

enum BranchSelector: Equatable, Hashable {
    case fixed(String)
    case rule(prefix: String, separator: String, format: BranchDateFormat)
    case regex(String)

    var displayHint: String {
        switch self {
        case .fixed(let branch):
            return branch
        case .rule(let prefix, let separator, let format):
            return "\(prefix)\(separator)\(format.displayName)"
        case .regex(let pattern):
            return pattern
        }
    }

    var compiledRegex: String? {
        switch self {
        case .fixed:
            return nil
        case .rule(let prefix, let separator, let format):
            return format.regex(prefix: prefix, separator: separator)
        case .regex(let pattern):
            return pattern
        }
    }

    var searchPrefix: String? {
        switch self {
        case .fixed:
            return nil
        case .rule(let prefix, let separator, _):
            return "\(prefix)\(separator)"
        case .regex(let pattern):
            return pattern.leadingLiteralPrefixFromAnchoredRegex
        }
    }
}

private extension String {
    var leadingLiteralPrefixFromAnchoredRegex: String? {
        guard first == "^" else { return nil }
        var prefix = ""
        var index = self.index(after: startIndex)
        let metacharacters = Set(".+*?()[]{}|$^")

        while index < endIndex {
            let character = self[index]
            if character == "\\" {
                let escapedIndex = self.index(after: index)
                guard escapedIndex < endIndex else { break }
                let escaped = self[escapedIndex]
                if metacharacters.contains(escaped) || escaped == "/" || escaped == "-" {
                    prefix.append(escaped)
                    index = self.index(after: escapedIndex)
                    continue
                }
                break
            }
            if metacharacters.contains(character) { break }
            prefix.append(character)
            index = self.index(after: index)
        }

        return prefix.isEmpty ? nil : prefix
    }
}

extension BranchSelector: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case prefix
        case separator
        case format
    }

    private enum Kind: String, Codable {
        case fixed
        case rule
        case regex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let branch):
            try container.encode(Kind.fixed, forKey: .type)
            try container.encode(branch, forKey: .value)
        case .rule(let prefix, let separator, let format):
            try container.encode(Kind.rule, forKey: .type)
            try container.encode(prefix, forKey: .prefix)
            try container.encode(separator, forKey: .separator)
            try container.encode(format, forKey: .format)
        case .regex(let pattern):
            try container.encode(Kind.regex, forKey: .type)
            try container.encode(pattern, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .fixed:
            self = .fixed(try container.decode(String.self, forKey: .value))
        case .rule:
            self = .rule(
                prefix: try container.decode(String.self, forKey: .prefix),
                separator: try container.decodeIfPresent(String.self, forKey: .separator) ?? "-",
                format: try container.decode(BranchDateFormat.self, forKey: .format)
            )
        case .regex:
            self = .regex(try container.decode(String.self, forKey: .value))
        }
    }
}

enum MonitorBranchRole: String, Codable, CaseIterable, Hashable {
    case production
    case testing
    case custom

    var displayName: String {
        switch self {
        case .production: return "生产分支"
        case .testing: return "测试分支"
        case .custom: return "其他分支"
        }
    }

    var shortName: String {
        switch self {
        case .production: return "生产"
        case .testing: return "测试"
        case .custom: return "其他"
        }
    }
}

struct MonitorBranchWatch: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var selector: BranchSelector
    var ciSelector: BranchSelector?
    var role: MonitorBranchRole
    var monitorEnabled: Bool

    var pipelineSelector: BranchSelector {
        ciSelector ?? selector
    }

    var ciSummary: String {
        guard let ciSelector, ciSelector != selector else {
            return selector.displayHint
        }
        return "\(selector.displayHint) -> CI/CD: \(ciSelector.displayHint)"
    }

    var roleSummary: String {
        monitorEnabled ? ciSummary : "\(selector.displayHint)（仅标记）"
    }

    init(
        id: UUID = UUID(),
        selector: BranchSelector,
        ciSelector: BranchSelector? = nil,
        role: MonitorBranchRole = .custom,
        monitorEnabled: Bool = true
    ) {
        self.id = id
        self.selector = selector
        self.ciSelector = ciSelector
        self.role = role
        self.monitorEnabled = monitorEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case selector
        case ciSelector
        case role
        case monitorEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        selector = try container.decode(BranchSelector.self, forKey: .selector)
        ciSelector = try container.decodeIfPresent(BranchSelector.self, forKey: .ciSelector)
        role = try container.decodeIfPresent(MonitorBranchRole.self, forKey: .role) ?? .custom
        monitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .monitorEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(selector, forKey: .selector)
        try container.encodeIfPresent(ciSelector, forKey: .ciSelector)
        try container.encode(role, forKey: .role)
        try container.encode(monitorEnabled, forKey: .monitorEnabled)
    }
}
