import Foundation

enum DeveloperToolCategory: String, CaseIterable, Identifiable {
    case data
    case encoding
    case diagnostics
    case generators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: return "数据处理"
        case .encoding: return "编码与摘要"
        case .diagnostics: return "调试与测试"
        case .generators: return "生成与转换"
        }
    }
}

struct DeveloperToolAction: Identifiable, Hashable {
    let id: String
    let title: String
}

enum DeveloperToolID: String, CaseIterable, Identifiable {
    case json
    case jwt
    case sql
    case url
    case headers
    case cookie
    case base64
    case hash
    case timestamp
    case cron
    case uuid
    case regex
    case text
    case textStats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "JSON 工作台"
        case .jwt: return "JWT 解析"
        case .sql: return "SQL 转换"
        case .url: return "URL 工具"
        case .headers: return "Header 解析"
        case .cookie: return "Cookie 解析"
        case .base64: return "Base64"
        case .hash: return "文本摘要"
        case .timestamp: return "时间戳转换"
        case .cron: return "Cron 解析"
        case .uuid: return "UUID 生成"
        case .regex: return "正则测试"
        case .text: return "文本转换"
        case .textStats: return "文本统计"
        }
    }

    var subtitle: String {
        switch self {
        case .json: return "格式化、压缩、排序、对比和保存"
        case .jwt: return "解析 Header、Payload 和有效期"
        case .sql: return "INSERT 转 JSON 和 Elasticsearch Bulk"
        case .url: return "解析、编码和解码 URL"
        case .headers: return "请求/响应头解析、去重和脱敏"
        case .cookie: return "Cookie 与 Set-Cookie 结构化"
        case .base64: return "UTF-8 文本编码与解码"
        case .hash: return "MD5、SHA1、SHA256、SHA512"
        case .timestamp: return "Unix 时间戳与日期互转"
        case .cron: return "5 段 Cron 未来执行时间"
        case .uuid: return "批量生成 UUID v4"
        case .regex: return "匹配结果与捕获组检查"
        case .text: return "大小写、命名和行处理"
        case .textStats: return "字符、行、词、中文和数字统计"
        }
    }

    var systemImage: String {
        switch self {
        case .json: return "curlybraces"
        case .jwt: return "key.horizontal"
        case .sql: return "tablecells"
        case .url: return "link"
        case .headers: return "list.bullet.rectangle"
        case .cookie: return "shippingbox"
        case .base64: return "textformat.abc"
        case .hash: return "number"
        case .timestamp: return "clock.arrow.circlepath"
        case .cron: return "calendar.badge.clock"
        case .uuid: return "dice"
        case .regex: return "text.magnifyingglass"
        case .text: return "textformat"
        case .textStats: return "text.word.spacing"
        }
    }

    var category: DeveloperToolCategory {
        switch self {
        case .json, .jwt, .sql:
            return .data
        case .url, .headers, .cookie, .base64, .hash:
            return .encoding
        case .timestamp, .cron, .regex:
            return .diagnostics
        case .uuid, .text, .textStats:
            return .generators
        }
    }

    var actions: [DeveloperToolAction] {
        switch self {
        case .json:
            return [
                DeveloperToolAction(id: "format", title: "格式化"),
                DeveloperToolAction(id: "minify", title: "压缩"),
                DeveloperToolAction(id: "sort", title: "排序 Key"),
                DeveloperToolAction(id: "compare", title: "JSON 对比")
            ]
        case .jwt:
            return [DeveloperToolAction(id: "decode", title: "解析")]
        case .sql:
            return [
                DeveloperToolAction(id: "insert-json", title: "INSERT → JSON"),
                DeveloperToolAction(id: "insert-bulk", title: "INSERT → ES Bulk")
            ]
        case .url:
            return [
                DeveloperToolAction(id: "parse", title: "解析"),
                DeveloperToolAction(id: "encode", title: "编码"),
                DeveloperToolAction(id: "decode", title: "解码")
            ]
        case .headers:
            return [
                DeveloperToolAction(id: "parse", title: "解析"),
                DeveloperToolAction(id: "json", title: "转 JSON")
            ]
        case .cookie:
            return [
                DeveloperToolAction(id: "parse-cookie", title: "Cookie"),
                DeveloperToolAction(id: "parse-set-cookie", title: "Set-Cookie")
            ]
        case .base64:
            return [
                DeveloperToolAction(id: "encode", title: "编码"),
                DeveloperToolAction(id: "decode", title: "解码")
            ]
        case .hash:
            return [
                DeveloperToolAction(id: "md5", title: "MD5"),
                DeveloperToolAction(id: "sha1", title: "SHA1"),
                DeveloperToolAction(id: "sha256", title: "SHA256"),
                DeveloperToolAction(id: "sha512", title: "SHA512")
            ]
        case .timestamp:
            return [
                DeveloperToolAction(id: "to-date", title: "时间戳 → 日期"),
                DeveloperToolAction(id: "to-timestamp", title: "日期 → 时间戳")
            ]
        case .cron:
            return [DeveloperToolAction(id: "next", title: "未来 5 次")]
        case .uuid:
            return [DeveloperToolAction(id: "generate", title: "生成")]
        case .regex:
            return [DeveloperToolAction(id: "match", title: "匹配")]
        case .text:
            return [
                DeveloperToolAction(id: "lower", title: "小写"),
                DeveloperToolAction(id: "upper", title: "大写"),
                DeveloperToolAction(id: "camel", title: "camelCase"),
                DeveloperToolAction(id: "snake", title: "snake_case"),
                DeveloperToolAction(id: "constant", title: "CONSTANT_CASE"),
                DeveloperToolAction(id: "trim", title: "清理空行"),
                DeveloperToolAction(id: "dedupe", title: "行去重"),
                DeveloperToolAction(id: "sort", title: "行排序")
            ]
        case .textStats:
            return [DeveloperToolAction(id: "stats", title: "统计")]
        }
    }

    var defaultInput: String {
        switch self {
        case .json:
            return "{\"name\":\"MyHelper\",\"enabled\":true,\"tools\":[\"json\",\"jwt\"]}"
        case .jwt:
            return ""
        case .sql:
            return "INSERT INTO users (id, name, enabled) VALUES (1, 'Alice', true), (2, 'Bob', false);"
        case .url:
            return "https://example.com/api?q=hello%20world&page=1"
        case .headers:
            return "GET /api/users HTTP/1.1\nHost: example.com\nAuthorization: Bearer token\nContent-Type: application/json"
        case .cookie:
            return "sid=abc123; theme=dark; lang=zh-CN"
        case .base64:
            return "Hello, MyHelper"
        case .hash:
            return "Hello, MyHelper"
        case .timestamp:
            return String(Int(Date().timeIntervalSince1970))
        case .cron:
            return "*/5 * * * *"
        case .uuid:
            return ""
        case .regex:
            return "user@example.com\ninvalid-email\nadmin@example.org"
        case .text:
            return "hello developer toolkit\nhello developer toolkit"
        case .textStats:
            return "Hello, MyHelper\n研发工具包 2026"
        }
    }

    var needsInputEditor: Bool { self != .uuid }
    var needsRegexPattern: Bool { self == .regex }
    var supportsIndent: Bool { self == .json }
    var supportsUUIDOptions: Bool { self == .uuid }
    var supportsRegexOptions: Bool { self == .regex }
}

struct DeveloperToolRequest {
    let tool: DeveloperToolID
    let action: String
    let input: String
    let regexPattern: String
    let jsonIndent: Int
    let regexCaseInsensitive: Bool
    let regexMultiline: Bool
    let uuidCount: Int
    let uuidUppercase: Bool
}

enum DeveloperToolError: LocalizedError {
    case emptyInput
    case invalidInput(String)
    case unsupportedAction
    case inputTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入要处理的内容"
        case let .invalidInput(message):
            return message
        case .unsupportedAction:
            return "当前工具不支持该操作"
        case .inputTooLarge:
            return "输入超过 1000 万字符，请使用专用流式工具处理"
        }
    }
}
