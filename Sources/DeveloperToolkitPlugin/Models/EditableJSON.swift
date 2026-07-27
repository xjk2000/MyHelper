import CoreFoundation
import Foundation

struct EditableJSONNode: Identifiable, Equatable {
    let id: UUID
    var value: EditableJSONValue

    init(id: UUID = UUID(), value: EditableJSONValue) {
        self.id = id
        self.value = value
    }

    static func parse(_ text: String) throws -> EditableJSONNode {
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            throw EditableJSONError.invalidJSON("JSON 内容为空")
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return fromFoundationValue(object)
        } catch {
            throw EditableJSONError.invalidJSON(error.localizedDescription)
        }
    }

    static func parseEditedValue(_ text: String) throws -> EditableJSONNode {
        let rawValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return EditableJSONNode(value: .string(""))
        }

        if let data = rawValue.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return fromFoundationValue(object)
        }

        if rawValue.hasPrefix("{") || rawValue.hasPrefix("[") {
            throw EditableJSONError.invalidJSON("对象或数组必须是合法 JSON")
        }
        return EditableJSONNode(value: .string(text))
    }

    func formattedJSON(indent: Int = 2) -> String {
        value.formattedJSON(level: 0, indent: max(0, indent))
    }

    func compactJSON() -> String {
        value.formattedJSON(level: 0, indent: 0)
    }

    private static func fromFoundationValue(_ value: Any) -> EditableJSONNode {
        if let object = value as? [String: Any] {
            let members = object.map { key, value in
                EditableJSONMember(key: key, node: fromFoundationValue(value))
            }
            return EditableJSONNode(value: .object(members))
        }
        if let array = value as? [Any] {
            return EditableJSONNode(value: .array(array.map(fromFoundationValue)))
        }
        if let string = value as? String {
            return EditableJSONNode(value: .string(string))
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return EditableJSONNode(value: .bool(number.boolValue))
            }
            return EditableJSONNode(value: .number(number.stringValue))
        }
        return EditableJSONNode(value: .null)
    }
}

struct EditableJSONMember: Identifiable, Equatable {
    let id: UUID
    var key: String
    var node: EditableJSONNode

    init(id: UUID = UUID(), key: String, node: EditableJSONNode) {
        self.id = id
        self.key = key
        self.node = node
    }
}

indirect enum EditableJSONValue: Equatable {
    case object([EditableJSONMember])
    case array([EditableJSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var isContainer: Bool {
        switch self {
        case .object, .array: return true
        case .string, .number, .bool, .null: return false
        }
    }

    var count: Int? {
        switch self {
        case let .object(members): return members.count
        case let .array(items): return items.count
        case .string, .number, .bool, .null: return nil
        }
    }

    var typeName: String {
        switch self {
        case .object: return "Object"
        case .array: return "Array"
        case .string: return "String"
        case .number: return "Number"
        case .bool: return "Boolean"
        case .null: return "Null"
        }
    }

    var displayValue: String {
        switch self {
        case let .object(members): return "{ \(members.count) }"
        case let .array(items): return "[ \(items.count) ]"
        case let .string(value): return "\"\(value)\""
        case let .number(value): return value
        case let .bool(value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    fileprivate func formattedJSON(level: Int, indent: Int) -> String {
        switch self {
        case let .object(members):
            guard !members.isEmpty else { return "{}" }
            if indent == 0 {
                return "{" + members.map { "\(jsonQuoted($0.key)):\($0.node.value.formattedJSON(level: level + 1, indent: 0))" }.joined(separator: ",") + "}"
            }
            let childIndent = String(repeating: " ", count: (level + 1) * indent)
            let closingIndent = String(repeating: " ", count: level * indent)
            let body = members.map {
                "\(childIndent)\(jsonQuoted($0.key)): \($0.node.value.formattedJSON(level: level + 1, indent: indent))"
            }.joined(separator: ",\n")
            return "{\n\(body)\n\(closingIndent)}"
        case let .array(items):
            guard !items.isEmpty else { return "[]" }
            if indent == 0 {
                return "[" + items.map { $0.value.formattedJSON(level: level + 1, indent: 0) }.joined(separator: ",") + "]"
            }
            let childIndent = String(repeating: " ", count: (level + 1) * indent)
            let closingIndent = String(repeating: " ", count: level * indent)
            let body = items.map {
                "\(childIndent)\($0.value.formattedJSON(level: level + 1, indent: indent))"
            }.joined(separator: ",\n")
            return "[\n\(body)\n\(closingIndent)]"
        case let .string(value):
            return jsonQuoted(value)
        case let .number(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private func jsonQuoted(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return text
    }
}

private func jsonQuoted(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
          let text = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return text
}

enum EditableJSONError: LocalizedError {
    case invalidJSON(String)
    case emptyKey
    case duplicateKey(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(message): return "JSON 无效：\(message)"
        case .emptyKey: return "Key 不能为空"
        case let .duplicateKey(key): return "同级已存在 Key：\(key)"
        }
    }
}
