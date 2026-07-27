import CryptoKit
import Foundation

enum DeveloperToolProcessor {
    private static let inputCharacterLimit = 10_000_000

    static func process(_ request: DeveloperToolRequest) throws -> String {
        guard request.input.count <= inputCharacterLimit else {
            throw DeveloperToolError.inputTooLarge
        }

        switch request.tool {
        case .json:
            return try processJSON(request)
        case .jwt:
            return try decodeJWT(request.input)
        case .sql:
            return try processSQL(request)
        case .url:
            return try processURL(request)
        case .headers:
            return try processHeaders(request)
        case .cookie:
            return try processCookie(request)
        case .base64:
            return try processBase64(request)
        case .hash:
            return try processHash(request)
        case .timestamp:
            return try processTimestamp(request)
        case .cron:
            return try processCron(request)
        case .uuid:
            return generateUUIDs(count: request.uuidCount, uppercase: request.uuidUppercase)
        case .regex:
            return try testRegex(request)
        case .text:
            return try transformText(request)
        case .textStats:
            return textStatistics(request.input)
        }
    }

    private static func processJSON(_ request: DeveloperToolRequest) throws -> String {
        guard let data = request.input.data(using: .utf8), !data.isEmpty else {
            throw DeveloperToolError.emptyInput
        }

        switch request.action {
        case "format":
            return formatJSONLenient(request.input, indent: request.jsonIndent)
        case "minify":
            return minifyJSONPreservingOrder(request.input)
        default:
            break
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            switch request.action {
            case "validate":
                return "JSON 有效\n根类型：\(jsonRootType(object))"
            case "sort":
                return try serializeJSON(object, pretty: true, sorted: true, indent: request.jsonIndent)
            default:
                throw DeveloperToolError.unsupportedAction
            }
        } catch let error as DeveloperToolError {
            throw error
        } catch {
            throw DeveloperToolError.invalidInput("JSON 解析失败：\(error.localizedDescription)")
        }
    }

    static func isValidJSON(_ input: String) -> Bool {
        guard let data = input.data(using: .utf8), !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    static func formatJSONLenient(_ input: String, indent: Int) -> String {
        guard input.count <= inputCharacterLimit else { return input }
        guard !input.isEmpty else { return "" }
        return lenientJSONIndent(input, indent: indent)
    }

    private static func minifyJSONPreservingOrder(_ input: String) -> String {
        var result = ""
        var inString = false
        var escaped = false

        for character in input {
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
            } else if !character.isWhitespace {
                result.append(character)
            }
        }

        return result
    }

    private static func serializeJSON(
        _ object: Any,
        pretty: Bool,
        sorted: Bool,
        indent: Int
    ) throws -> String {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted) }
        if sorted { options.insert(.sortedKeys) }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        guard var output = String(data: data, encoding: .utf8) else {
            throw DeveloperToolError.invalidInput("无法生成 UTF-8 JSON")
        }

        if pretty, indent == 4 {
            output = output
                .components(separatedBy: "\n")
                .map { line in
                    let leadingSpaces = line.prefix { $0 == " " }.count
                    return String(repeating: " ", count: leadingSpaces * 2) + line.dropFirst(leadingSpaces)
                }
                .joined(separator: "\n")
        }
        return output
    }

    private static func lenientJSONIndent(_ input: String, indent: Int) -> String {
        let characters = Array(input)
        var result = ""
        var level = 0
        var inString = false
        var escaped = false
        var lastSignificant: Character?
        let unit = String(repeating: " ", count: indent)
        var index = 0

        func trimTrailingSpaces() {
            while result.last == " " || result.last == "\t" {
                result.removeLast()
            }
        }

        func appendNewline() {
            trimTrailingSpaces()
            while result.last == "\n" {
                result.removeLast()
            }
            result.append("\n")
            result.append(String(repeating: unit, count: max(level, 0)))
        }

        func appendSpaceIfNeeded() {
            guard let last = result.last, last != " ", last != "\n" else { return }
            result.append(" ")
        }

        func isPunctuation(_ character: Character) -> Bool {
            character == "{"
                || character == "}"
                || character == "["
                || character == "]"
                || character == ","
                || character == ":"
        }

        func nextNonWhitespaceIndex(after start: Int) -> Int? {
            var cursor = start
            while cursor < characters.count {
                if !characters[cursor].isWhitespace {
                    return cursor
                }
                cursor += 1
            }
            return nil
        }

        while index < characters.count {
            let character = characters[index]

            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }

            if character.isWhitespace {
                index += 1
                continue
            }

            switch character {
            case "\"":
                if let lastSignificant,
                   lastSignificant != "{",
                   lastSignificant != "[",
                   lastSignificant != ":",
                   lastSignificant != "," {
                    appendSpaceIfNeeded()
                }
                inString = true
                result.append(character)
                lastSignificant = character
            case "{", "[":
                if let lastSignificant,
                   lastSignificant != "{",
                   lastSignificant != "[",
                   lastSignificant != ":",
                   lastSignificant != "," {
                    appendSpaceIfNeeded()
                }
                result.append(character)
                lastSignificant = character
                let closing: Character = character == "{" ? "}" : "]"
                if let closeIndex = nextNonWhitespaceIndex(after: index + 1),
                   characters[closeIndex] == closing {
                    result.append(closing)
                    lastSignificant = closing
                    index = closeIndex
                } else {
                    level += 1
                    appendNewline()
                }
            case "}", "]":
                level = max(level - 1, 0)
                appendNewline()
                result.append(character)
                lastSignificant = character
            case ",":
                trimTrailingSpaces()
                result.append(character)
                lastSignificant = character
                appendNewline()
            case ":":
                trimTrailingSpaces()
                result.append(": ")
                lastSignificant = character
            default:
                if let lastSignificant,
                   lastSignificant != "{",
                   lastSignificant != "[",
                   lastSignificant != ":",
                   lastSignificant != "," {
                    appendSpaceIfNeeded()
                }
                var token = ""
                var cursor = index
                while cursor < characters.count,
                      !characters[cursor].isWhitespace,
                      characters[cursor] != "\"",
                      !isPunctuation(characters[cursor]) {
                    token.append(characters[cursor])
                    cursor += 1
                }
                if token.isEmpty {
                    result.append(character)
                    lastSignificant = character
                } else {
                    result.append(token)
                    lastSignificant = token.last
                    index = cursor - 1
                }
            }

            index += 1
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jsonRootType(_ value: Any) -> String {
        switch value {
        case is [String: Any]: return "Object"
        case is [Any]: return "Array"
        case is String: return "String"
        case is NSNumber: return "Number / Boolean"
        case is NSNull: return "Null"
        default: return String(describing: type(of: value))
        }
    }

    private static func decodeJWT(_ input: String) throws -> String {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw DeveloperToolError.emptyInput }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw DeveloperToolError.invalidInput("JWT 必须包含 Header、Payload 和 Signature 三段")
        }

        let header = try decodeBase64URL(String(parts[0]), section: "Header")
        let payload = try decodeBase64URL(String(parts[1]), section: "Payload")
        let headerText = try prettyJSONData(header, section: "Header")
        let payloadText = try prettyJSONData(payload, section: "Payload")

        var metadata = ["签名：未验证"]
        if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let expiresAt = numberValue(object["exp"]) {
            let expiration = Date(timeIntervalSince1970: expiresAt)
            metadata.append("过期时间：\(localDateFormatter.string(from: expiration))")
            metadata.append(expiration <= Date() ? "状态：已过期" : "状态：有效期内")
        } else {
            metadata.append("状态：Payload 未包含 exp")
        }

        return "Header\n\(headerText)\n\nPayload\n\(payloadText)\n\n\(metadata.joined(separator: "\n"))"
    }

    private static func decodeBase64URL(_ value: String, section: String) throws -> Data {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized) else {
            throw DeveloperToolError.invalidInput("JWT \(section) 不是有效的 Base64URL")
        }
        return data
    }

    private static func prettyJSONData(_ data: Data, section: String) throws -> String {
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return try serializeJSON(object, pretty: true, sorted: false, indent: 2)
        } catch {
            throw DeveloperToolError.invalidInput("JWT \(section) 不是有效 JSON")
        }
    }

    private static func processSQL(_ request: DeveloperToolRequest) throws -> String {
        let parsed = try parseInsertSQL(request.input)
        switch request.action {
        case "insert-json":
            return try serializeJSON(parsed.rows, pretty: true, sorted: false, indent: request.jsonIndent)
        case "insert-bulk":
            let indexName = parsed.table.isEmpty ? "my_index" : parsed.table
            let lines = parsed.rows.flatMap { row -> [String] in
                let meta = ["index": ["_index": indexName]]
                let metaText = (try? serializeJSON(meta, pretty: false, sorted: false, indent: 2)) ?? "{\"index\":{\"_index\":\"\(indexName)\"}}"
                let rowText = (try? serializeJSON(row, pretty: false, sorted: false, indent: 2)) ?? "{}"
                return [metaText, rowText]
            }
            return lines.joined(separator: "\n") + "\n"
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func processHeaders(_ request: DeveloperToolRequest) throws -> String {
        let parsed = try parseHTTPHeaders(request.input)
        switch request.action {
        case "parse":
            let duplicateNames = parsed.duplicates.isEmpty ? "无" : parsed.duplicates.joined(separator: ", ")
            let rows = parsed.rows.map { row in
                "\(row.name): \(row.sensitive ? maskSensitiveValue(row.value) : row.value) [\(row.category)]"
            }
            return [
                parsed.startLine.isEmpty ? "HTTP Headers" : "Start-Line: \(parsed.startLine)",
                "Header 数量：\(parsed.rows.count)",
                "重复名称：\(duplicateNames)",
                "敏感字段：\(parsed.rows.filter(\.sensitive).count)",
                "",
                "fetch headers:",
                try serializeJSON(parsed.object, pretty: true, sorted: false, indent: 2),
                "",
                rows.joined(separator: "\n")
            ].joined(separator: "\n")
        case "json":
            return try serializeJSON(parsed.object, pretty: true, sorted: false, indent: request.jsonIndent)
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func processCookie(_ request: DeveloperToolRequest) throws -> String {
        switch request.action {
        case "parse-cookie":
            let rows = parseCookieHeader(request.input)
            guard !rows.isEmpty else {
                throw DeveloperToolError.invalidInput("没有解析到有效 Cookie，格式应为 sid=abc; theme=dark")
            }
            return try serializeJSON(rows, pretty: true, sorted: false, indent: request.jsonIndent)
        case "parse-set-cookie":
            let rows = parseSetCookieHeaders(request.input)
            guard !rows.isEmpty else {
                throw DeveloperToolError.invalidInput("没有解析到有效 Set-Cookie，每行一个 Set-Cookie")
            }
            return try serializeJSON(rows, pretty: true, sorted: false, indent: request.jsonIndent)
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func processURL(_ request: DeveloperToolRequest) throws -> String {
        switch request.action {
        case "encode":
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return request.input.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        case "decode":
            guard let value = request.input.removingPercentEncoding else {
                throw DeveloperToolError.invalidInput("URL 编码格式无效")
            }
            return value
        case "parse":
            let input = request.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { throw DeveloperToolError.emptyInput }
            guard let components = URLComponents(string: input), components.scheme != nil else {
                throw DeveloperToolError.invalidInput("请输入包含协议的完整 URL")
            }
            let items = components.queryItems ?? []
            let queryRows = items.map { item -> [String: Any] in
                ["name": item.name, "value": item.value ?? NSNull()]
            }
            let queryJSON = try serializeJSON(queryRows, pretty: true, sorted: false, indent: 2)
            let base = "\(components.scheme ?? "")://\(components.host ?? "")\(components.path)"
            return "基础 URL\n\(base)\n\nQuery 参数（\(items.count)）\n\(queryJSON)\n\nFragment\n\(components.fragment ?? "--")"
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func processBase64(_ request: DeveloperToolRequest) throws -> String {
        switch request.action {
        case "encode":
            return Data(request.input.utf8).base64EncodedString()
        case "decode":
            let normalized = request.input.filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: normalized),
                  let output = String(data: data, encoding: .utf8) else {
                throw DeveloperToolError.invalidInput("Base64 无效，或解码结果不是 UTF-8 文本")
            }
            return output
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func processHash(_ request: DeveloperToolRequest) throws -> String {
        let data = Data(request.input.utf8)
        switch request.action {
        case "md5":
            return hexDigest(Insecure.MD5.hash(data: data))
        case "sha1":
            return hexDigest(Insecure.SHA1.hash(data: data))
        case "sha256":
            return hexDigest(SHA256.hash(data: data))
        case "sha512":
            return hexDigest(SHA512.hash(data: data))
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func hexDigest<S: Sequence>(_ digest: S) -> String where S.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func processTimestamp(_ request: DeveloperToolRequest) throws -> String {
        let input = request.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw DeveloperToolError.emptyInput }

        switch request.action {
        case "to-date":
            guard let rawValue = Double(input) else {
                throw DeveloperToolError.invalidInput("时间戳必须是数字")
            }
            let isMilliseconds = abs(rawValue) >= 10_000_000_000
            let seconds = isMilliseconds ? rawValue / 1_000 : rawValue
            let date = Date(timeIntervalSince1970: seconds)
            return "本地时间\n\(localDateFormatter.string(from: date))\n\nISO 8601\n\(isoFormatter.string(from: date))\n\n秒\n\(Int64(seconds))\n\n毫秒\n\(Int64(seconds * 1_000))"
        case "to-timestamp":
            guard let date = parseDate(input) else {
                throw DeveloperToolError.invalidInput("支持 ISO 8601 或 yyyy-MM-dd HH:mm:ss 格式")
            }
            return "秒\n\(Int64(date.timeIntervalSince1970))\n\n毫秒\n\(Int64(date.timeIntervalSince1970 * 1_000))\n\n本地时间\n\(localDateFormatter.string(from: date))"
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func parseDate(_ input: String) -> Date? {
        if let date = isoFormatter.date(from: input) { return date }
        if let date = isoBasicFormatter.date(from: input) { return date }
        return localDateFormatter.date(from: input)
    }

    private static func processCron(_ request: DeveloperToolRequest) throws -> String {
        let schedule = try CronSchedule(expression: request.input)
        let dates = schedule.nextDates(count: 5, from: Date(), calendar: Calendar.current)
        guard !dates.isEmpty else {
            throw DeveloperToolError.invalidInput("未能在未来一年内计算到执行时间")
        }

        return [
            "表达式：\(schedule.expression)",
            "说明：5 段 Cron（分 时 日 月 周），按本机时区计算",
            "",
            dates.enumerated().map { index, date in
                "\(index + 1). \(localDateFormatter.string(from: date))"
            }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private static func generateUUIDs(count: Int, uppercase: Bool) -> String {
        (0..<min(max(count, 1), 100))
            .map { _ in
                let value = UUID().uuidString
                return uppercase ? value.uppercased() : value.lowercased()
            }
            .joined(separator: "\n")
    }

    private static func testRegex(_ request: DeveloperToolRequest) throws -> String {
        guard !request.regexPattern.isEmpty else {
            throw DeveloperToolError.invalidInput("请输入正则表达式")
        }

        var options: NSRegularExpression.Options = []
        if request.regexCaseInsensitive { options.insert(.caseInsensitive) }
        if request.regexMultiline { options.insert(.anchorsMatchLines) }

        do {
            let regex = try NSRegularExpression(pattern: request.regexPattern, options: options)
            let fullRange = NSRange(request.input.startIndex..<request.input.endIndex, in: request.input)
            let matches = regex.matches(in: request.input, range: fullRange)
            guard !matches.isEmpty else { return "未匹配到内容" }

            let rows = matches.enumerated().map { index, match in
                var lines = ["\(index + 1). \(substring(in: request.input, range: match.range) ?? "")"]
                if match.numberOfRanges > 1 {
                    for groupIndex in 1..<match.numberOfRanges {
                        let value = substring(in: request.input, range: match.range(at: groupIndex)) ?? "<未匹配>"
                        lines.append("   $\(groupIndex): \(value)")
                    }
                }
                lines.append("   range: \(match.range.location)..<\(match.range.location + match.range.length)")
                return lines.joined(separator: "\n")
            }
            return "匹配数：\(matches.count)\n\n\(rows.joined(separator: "\n\n"))"
        } catch {
            throw DeveloperToolError.invalidInput("正则表达式无效：\(error.localizedDescription)")
        }
    }

    private static func substring(in input: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: input) else { return nil }
        return String(input[swiftRange])
    }

    private static func transformText(_ request: DeveloperToolRequest) throws -> String {
        switch request.action {
        case "lower":
            return request.input.lowercased()
        case "upper":
            return request.input.uppercased()
        case "camel":
            let words = normalizedWords(request.input)
            guard let first = words.first else { return "" }
            return first.lowercased() + words.dropFirst().map { $0.capitalized }.joined()
        case "snake":
            return normalizedWords(request.input).map { $0.lowercased() }.joined(separator: "_")
        case "constant":
            return normalizedWords(request.input).map { $0.uppercased() }.joined(separator: "_")
        case "trim":
            return request.input
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case "dedupe":
            var seen = Set<String>()
            return request.input
                .components(separatedBy: .newlines)
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        case "sort":
            return request.input
                .components(separatedBy: .newlines)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .joined(separator: "\n")
        default:
            throw DeveloperToolError.unsupportedAction
        }
    }

    private static func normalizedWords(_ input: String) -> [String] {
        let expanded = input.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return expanded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func textStatistics(_ input: String) -> String {
        let lines = input.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let scalars = input.unicodeScalars
        let chineseCount = scalars.filter { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }.count
        let digitCount = input.filter(\.isNumber).count
        let letterCount = input.filter(\.isLetter).count
        let whitespaceCount = input.filter(\.isWhitespace).count
        let words = input
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return [
            "字符数：\(input.count)",
            "Unicode Scalar：\(scalars.count)",
            "行数：\(lines.count)",
            "非空行：\(nonEmptyLines.count)",
            "词/片段数：\(words.count)",
            "中文字数：\(chineseCount)",
            "字母数：\(letterCount)",
            "数字数：\(digitCount)",
            "空白字符：\(whitespaceCount)",
            "UTF-8 字节：\(Data(input.utf8).count)"
        ].joined(separator: "\n")
    }

    private struct ParsedInsertSQL {
        let table: String
        let rows: [[String: Any]]
    }

    private struct ParsedHeaderRow {
        let name: String
        let value: String
        let normalizedName: String
        let category: String
        let sensitive: Bool
    }

    private struct ParsedHeaders {
        let startLine: String
        let rows: [ParsedHeaderRow]
        let duplicates: [String]
        let object: [String: Any]
    }

    private static func parseInsertSQL(_ input: String) throws -> ParsedInsertSQL {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #";\s*$"#, with: "", options: .regularExpression)
        guard !normalized.isEmpty else { throw DeveloperToolError.emptyInput }

        let pattern = #"(?is)^\s*insert\s+into\s+([`"\w.\-]+)\s*\((.*?)\)\s*values\s*(.+)$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
            let tableRange = Range(match.range(at: 1), in: normalized),
            let columnsRange = Range(match.range(at: 2), in: normalized),
            let valuesRange = Range(match.range(at: 3), in: normalized)
        else {
            throw DeveloperToolError.invalidInput("暂仅支持 INSERT INTO table (a,b) VALUES (...), (...) 结构")
        }

        let table = stripSQLIdentifier(String(normalized[tableRange]))
        let columns = splitSQLCSV(String(normalized[columnsRange])).map { stripSQLIdentifier($0) }
        guard !columns.isEmpty else {
            throw DeveloperToolError.invalidInput("没有解析到列名")
        }

        let groups = try parseSQLValueGroups(String(normalized[valuesRange]))
        guard !groups.isEmpty else {
            throw DeveloperToolError.invalidInput("没有解析到 VALUES 数据")
        }

        let rows = groups.map { group -> [String: Any] in
            let values = splitSQLCSV(group).map(parseSQLValue)
            var row: [String: Any] = [:]
            for (index, column) in columns.enumerated() {
                row[column] = index < values.count ? values[index] : NSNull()
            }
            return row
        }

        return ParsedInsertSQL(table: table, rows: rows)
    }

    private static func parseSQLValueGroups(_ input: String) throws -> [String] {
        var groups: [String] = []
        var current = ""
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            let nextIndex = input.index(after: index)

            if inSingleQuote {
                if character == "'", nextIndex < input.endIndex, input[nextIndex] == "'" {
                    current.append(character)
                    current.append(input[nextIndex])
                    index = input.index(after: nextIndex)
                    continue
                }
                if character == "'" { inSingleQuote = false }
                current.append(character)
            } else if inDoubleQuote {
                if character == "\"" { inDoubleQuote = false }
                current.append(character)
            } else {
                switch character {
                case "'":
                    inSingleQuote = true
                    current.append(character)
                case "\"":
                    inDoubleQuote = true
                    current.append(character)
                case "(":
                    if depth > 0 { current.append(character) }
                    depth += 1
                case ")":
                    depth -= 1
                    if depth < 0 {
                        throw DeveloperToolError.invalidInput("VALUES 括号不匹配")
                    }
                    if depth == 0 {
                        groups.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                        current = ""
                    } else {
                        current.append(character)
                    }
                default:
                    if depth > 0 {
                        current.append(character)
                    }
                }
            }

            index = nextIndex
        }

        if inSingleQuote || inDoubleQuote || depth != 0 {
            throw DeveloperToolError.invalidInput("VALUES 语法不完整")
        }
        return groups
    }

    private static func splitSQLCSV(_ input: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var depth = 0
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            let nextIndex = input.index(after: index)

            if inSingleQuote {
                if character == "'", nextIndex < input.endIndex, input[nextIndex] == "'" {
                    current.append(character)
                    current.append(input[nextIndex])
                    index = input.index(after: nextIndex)
                    continue
                }
                if character == "'" { inSingleQuote = false }
                current.append(character)
            } else if inDoubleQuote {
                if character == "\"" { inDoubleQuote = false }
                current.append(character)
            } else {
                switch character {
                case "'":
                    inSingleQuote = true
                    current.append(character)
                case "\"":
                    inDoubleQuote = true
                    current.append(character)
                case "(", "[":
                    depth += 1
                    current.append(character)
                case ")", "]":
                    depth = max(depth - 1, 0)
                    current.append(character)
                case "," where depth == 0:
                    values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                default:
                    current.append(character)
                }
            }

            index = nextIndex
        }

        values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    private static func stripSQLIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "`" && last == "`") || (first == "\"" && last == "\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func parseSQLValue(_ rawValue: String) -> Any {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.caseInsensitiveCompare("null") == .orderedSame {
            return NSNull()
        }
        if value.caseInsensitiveCompare("true") == .orderedSame {
            return true
        }
        if value.caseInsensitiveCompare("false") == .orderedSame {
            return false
        }
        if value.count >= 2,
           value.first == "'",
           value.last == "'" {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if let integer = Int64(value) {
            return integer
        }
        if let double = Double(value) {
            return double
        }
        return value
    }

    private static func parseHTTPHeaders(_ input: String) throws -> ParsedHeaders {
        let normalized = input.replacingOccurrences(of: "\u{0000}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw DeveloperToolError.emptyInput }

        var startLine = ""
        var rows: [ParsedHeaderRow] = []
        var pendingName: String?
        var pendingValue = ""

        func flushPending() {
            guard let name = pendingName else { return }
            let normalizedName = name.lowercased()
            rows.append(
                ParsedHeaderRow(
                    name: name,
                    value: pendingValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    normalizedName: normalizedName,
                    category: headerCategory(normalizedName),
                    sensitive: isSensitiveHeader(normalizedName)
                )
            )
            pendingName = nil
            pendingValue = ""
        }

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if line.first?.isWhitespace == true, pendingName != nil {
                pendingValue += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard let colonIndex = line.firstIndex(of: ":") else {
                if startLine.isEmpty { startLine = line.trimmingCharacters(in: .whitespacesAndNewlines) }
                continue
            }
            flushPending()
            pendingName = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            pendingValue = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        flushPending()

        guard !rows.isEmpty else {
            throw DeveloperToolError.invalidInput("没有解析到有效 Header，格式应为 Key: Value")
        }

        var counts: [String: Int] = [:]
        var object: [String: Any] = [:]
        for row in rows {
            counts[row.normalizedName, default: 0] += 1
            if let existing = object[row.name] {
                if var array = existing as? [String] {
                    array.append(row.value)
                    object[row.name] = array
                } else if let string = existing as? String {
                    object[row.name] = [string, row.value]
                }
            } else {
                object[row.name] = row.value
            }
        }

        let duplicates = counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        return ParsedHeaders(startLine: startLine, rows: rows, duplicates: duplicates, object: object)
    }

    private static func headerCategory(_ normalizedName: String) -> String {
        if normalizedName == "cookie" || normalizedName == "set-cookie" { return "cookie" }
        if normalizedName.contains("auth") || normalizedName.contains("token") { return "auth" }
        if normalizedName.hasPrefix("access-control-") || normalizedName == "origin" { return "cors" }
        if normalizedName.contains("cache") || normalizedName == "etag" { return "cache" }
        if ["content-security-policy", "strict-transport-security", "x-frame-options", "x-content-type-options"].contains(normalizedName) {
            return "security"
        }
        return "general"
    }

    private static func isSensitiveHeader(_ normalizedName: String) -> Bool {
        normalizedName == "authorization"
            || normalizedName == "cookie"
            || normalizedName == "set-cookie"
            || normalizedName.contains("token")
            || normalizedName.contains("secret")
            || normalizedName.contains("api-key")
    }

    private static func maskSensitiveValue(_ value: String) -> String {
        guard value.count > 8 else { return "****" }
        return "\(value.prefix(4))...\(value.suffix(4))"
    }

    private static func parseCookieHeader(_ input: String) -> [[String: Any]] {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)^cookie\s*:\s*"#, with: "", options: .regularExpression)
        return splitCookieParts(normalized).compactMap { part in
            guard let equalsIndex = part.firstIndex(of: "=") else { return nil }
            let name = String(part[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let value = String(part[part.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ["name": name, "value": value]
        }
    }

    private static func parseSetCookieHeaders(_ input: String) -> [[String: Any]] {
        input.components(separatedBy: .newlines).compactMap { rawLine -> [String: Any]? in
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"(?i)^set-cookie\s*:\s*"#, with: "", options: .regularExpression)
            guard !line.isEmpty else { return nil }
            let parts = splitCookieParts(line)
            guard let first = parts.first, let equalsIndex = first.firstIndex(of: "=") else { return nil }
            var row: [String: Any] = [
                "name": String(first[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines),
                "value": String(first[first.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            for attribute in parts.dropFirst() {
                if let attributeEqualsIndex = attribute.firstIndex(of: "=") {
                    let key = String(attribute[..<attributeEqualsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(attribute[attribute.index(after: attributeEqualsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    row[key] = value
                } else {
                    row[attribute.trimmingCharacters(in: .whitespacesAndNewlines)] = true
                }
            }
            return row
        }
    }

    private static func splitCookieParts(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote = false
        for character in input {
            if character == "\"" {
                inQuote.toggle()
                current.append(character)
            } else if character == ";", !inQuote {
                let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { parts.append(value) }
                current = ""
            } else {
                current.append(character)
            }
        }
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { parts.append(value) }
        return parts
    }

    private struct CronSchedule {
        let expression: String
        let minutes: Set<Int>
        let hours: Set<Int>
        let daysOfMonth: Set<Int>
        let months: Set<Int>
        let daysOfWeek: Set<Int>

        init(expression input: String) throws {
            let fields = input.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard fields.count == 5 else {
                throw DeveloperToolError.invalidInput("当前只支持 5 段 Cron：分 时 日 月 周，例如 */5 * * * *")
            }
            expression = fields.joined(separator: " ")
            minutes = try CronSchedule.parseField(fields[0], range: 0...59, name: "分钟")
            hours = try CronSchedule.parseField(fields[1], range: 0...23, name: "小时")
            daysOfMonth = try CronSchedule.parseField(fields[2], range: 1...31, name: "日")
            months = try CronSchedule.parseField(fields[3], range: 1...12, name: "月")
            daysOfWeek = try CronSchedule.parseField(fields[4], range: 0...7, name: "周").map { $0 == 7 ? 0 : $0 }.reduce(into: Set<Int>()) { $0.insert($1) }
        }

        func nextDates(count: Int, from date: Date, calendar: Calendar) -> [Date] {
            var results: [Date] = []
            guard let start = calendar.date(byAdding: .minute, value: 1, to: date) else { return [] }
            var candidate = calendar.dateInterval(of: .minute, for: start)?.start ?? start
            let end = calendar.date(byAdding: .day, value: 366, to: date) ?? date

            while candidate <= end && results.count < count {
                if matches(candidate, calendar: calendar) {
                    results.append(candidate)
                }
                guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else { break }
                candidate = next
            }
            return results
        }

        private func matches(_ date: Date, calendar: Calendar) -> Bool {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
            guard
                let minute = components.minute,
                let hour = components.hour,
                let day = components.day,
                let month = components.month,
                let weekday = components.weekday
            else {
                return false
            }
            let cronWeekday = (weekday + 6) % 7
            return minutes.contains(minute)
                && hours.contains(hour)
                && daysOfMonth.contains(day)
                && months.contains(month)
                && daysOfWeek.contains(cronWeekday)
        }

        private static func parseField(_ field: String, range: ClosedRange<Int>, name: String) throws -> Set<Int> {
            var values = Set<Int>()
            for part in field.split(separator: ",").map(String.init) {
                let stepParts = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard stepParts.count <= 2 else {
                    throw DeveloperToolError.invalidInput("\(name) 字段无效：\(field)")
                }
                let base = stepParts[0]
                let step = stepParts.count == 2 ? (Int(stepParts[1]) ?? 0) : 1
                guard step > 0 else {
                    throw DeveloperToolError.invalidInput("\(name) 步长必须大于 0")
                }

                let baseRange: ClosedRange<Int>
                if base == "*" {
                    baseRange = range
                } else if base.contains("-") {
                    let bounds = base.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
                    guard bounds.count == 2, bounds[0] <= bounds[1] else {
                        throw DeveloperToolError.invalidInput("\(name) 范围无效：\(base)")
                    }
                    baseRange = bounds[0]...bounds[1]
                } else if let value = Int(base) {
                    baseRange = value...value
                } else {
                    throw DeveloperToolError.invalidInput("\(name) 字段无效：\(field)")
                }

                for value in stride(from: baseRange.lowerBound, through: baseRange.upperBound, by: step) {
                    guard range.contains(value) else {
                        throw DeveloperToolError.invalidInput("\(name) 超出范围：\(value)")
                    }
                    values.insert(value)
                }
            }
            return values
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasicFormatter = ISO8601DateFormatter()

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
