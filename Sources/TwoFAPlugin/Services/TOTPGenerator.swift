import CryptoKit
import Foundation

enum TOTPGenerator {
    static func code(for account: TOTPAccount, at date: Date = Date()) -> String? {
        do {
            let secretData = try Base32Decoder.decode(account.secret)
            return generate(secretData: secretData, date: date, digits: account.digits, period: account.period)
        } catch {
            return nil
        }
    }

    static func remainingSeconds(for account: TOTPAccount, at date: Date = Date()) -> Int {
        let period = max(account.period, 1)
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    static func progress(for account: TOTPAccount, at date: Date = Date()) -> Double {
        let period = max(account.period, 1)
        let remaining = remainingSeconds(for: account, at: date)
        return Double(remaining) / Double(period)
    }

    static func validate(secret: String) throws {
        _ = try Base32Decoder.decode(secret)
    }

    private static func generate(secretData: Data, date: Date, digits: Int, period: Int) -> String {
        let validDigits = min(max(digits, 6), 8)
        let validPeriod = max(period, 1)
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(validPeriod)))
        let counterData = Data([
            UInt8((counter >> 56) & 0xff),
            UInt8((counter >> 48) & 0xff),
            UInt8((counter >> 40) & 0xff),
            UInt8((counter >> 32) & 0xff),
            UInt8((counter >> 24) & 0xff),
            UInt8((counter >> 16) & 0xff),
            UInt8((counter >> 8) & 0xff),
            UInt8(counter & 0xff)
        ])

        let key = SymmetricKey(data: secretData)
        let authenticationCode = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let bytes = Array(authenticationCode)
        let offset = Int(bytes[bytes.count - 1] & 0x0f)
        let truncatedHash = (
            (Int(bytes[offset] & 0x7f) << 24) |
            (Int(bytes[offset + 1] & 0xff) << 16) |
            (Int(bytes[offset + 2] & 0xff) << 8) |
            Int(bytes[offset + 3] & 0xff)
        )

        let divisor = (0..<validDigits).reduce(1) { value, _ in value * 10 }
        let code = truncatedHash % divisor
        return String(format: "%0\(validDigits)d", code)
    }
}
