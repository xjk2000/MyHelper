import Foundation

struct TOTPAccount: Identifiable, Codable, Equatable {
    var id: UUID
    var issuer: String
    var name: String
    var secret: String
    var digits: Int
    var period: Int

    init(
        id: UUID = UUID(),
        issuer: String,
        name: String,
        secret: String,
        digits: Int = 6,
        period: Int = 30
    ) {
        self.id = id
        self.issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secret = secret.normalizedBase32Secret
        self.digits = digits
        self.period = period
    }

    var displayName: String {
        if issuer.isEmpty {
            return name.isEmpty ? "Untitled" : name
        }

        if name.isEmpty || name == issuer {
            return issuer
        }

        return "\(issuer) - \(name)"
    }

    var shortMenuName: String {
        let value = displayName
        guard value.count > 24 else { return value }
        return String(value.prefix(21)) + "..."
    }
}

extension String {
    var normalizedBase32Secret: String {
        uppercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
    }
}
