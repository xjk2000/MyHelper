import Foundation

enum AccountInputParser {
    enum ParseError: LocalizedError {
        case missingSecret
        case unsupportedURL
        case invalidSecret(String)

        var errorDescription: String? {
            switch self {
            case .missingSecret:
                return "请填写 Secret 或 otpauth:// 链接"
            case .unsupportedURL:
                return "只支持 otpauth://totp/... 格式"
            case .invalidSecret(let message):
                return message
            }
        }
    }

    static func account(
        issuer: String,
        name: String,
        secretOrURL: String,
        digits: Int,
        period: Int,
        existingID: UUID? = nil
    ) throws -> TOTPAccount {
        let input = secretOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ParseError.missingSecret }

        if input.lowercased().hasPrefix("otpauth://") {
            return try account(fromOTPAuthURL: input, existingID: existingID)
        }

        do {
            try TOTPGenerator.validate(secret: input)
        } catch {
            throw ParseError.invalidSecret(error.localizedDescription)
        }

        return TOTPAccount(
            id: existingID ?? UUID(),
            issuer: issuer,
            name: name,
            secret: input,
            digits: digits,
            period: period
        )
    }

    private static func account(fromOTPAuthURL input: String, existingID: UUID?) throws -> TOTPAccount {
        guard
            let components = URLComponents(string: input),
            components.scheme?.lowercased() == "otpauth",
            components.host?.lowercased() == "totp"
        else {
            throw ParseError.unsupportedURL
        }

        let queryItems = components.queryItems ?? []
        func queryValue(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name.lowercased() }?.value
        }

        guard let secret = queryValue("secret"), !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.missingSecret
        }

        do {
            try TOTPGenerator.validate(secret: secret)
        } catch {
            throw ParseError.invalidSecret(error.localizedDescription)
        }

        let rawLabel = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let label = rawLabel.removingPercentEncoding ?? rawLabel
        let labelParts = label.split(separator: ":", maxSplits: 1).map(String.init)
        let issuerFromLabel = labelParts.first ?? ""
        let nameFromLabel = labelParts.count > 1 ? labelParts[1] : issuerFromLabel

        let issuer = queryValue("issuer") ?? issuerFromLabel
        let digits = Int(queryValue("digits") ?? "") ?? 6
        let period = Int(queryValue("period") ?? "") ?? 30

        return TOTPAccount(
            id: existingID ?? UUID(),
            issuer: issuer,
            name: nameFromLabel,
            secret: secret,
            digits: digits,
            period: period
        )
    }
}
