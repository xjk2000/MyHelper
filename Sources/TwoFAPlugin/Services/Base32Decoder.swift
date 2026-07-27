import Foundation

enum Base32Decoder {
    enum DecodeError: LocalizedError {
        case invalidCharacter(Character)
        case emptySecret

        var errorDescription: String? {
            switch self {
            case .invalidCharacter(let character):
                return "Secret 包含无效字符：\(character)"
            case .emptySecret:
                return "Secret 不能为空"
            }
        }
    }

    private static let alphabet: [Character: UInt8] = {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($0.element, UInt8($0.offset)) })
    }()

    static func decode(_ secret: String) throws -> Data {
        let normalized = secret.normalizedBase32Secret
        guard !normalized.isEmpty else { throw DecodeError.emptySecret }

        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []

        for character in normalized {
            guard let value = alphabet[character] else {
                throw DecodeError.invalidCharacter(character)
            }

            buffer = (buffer << 5) | Int(value)
            bitsLeft += 5

            if bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 0xff))
                bitsLeft -= 8
            }
        }

        return Data(bytes)
    }
}
