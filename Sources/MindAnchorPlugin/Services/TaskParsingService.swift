import Foundation

protocol TaskParsingService: Sendable {
    func parse(input: TaskParseInput) async throws -> ParsedTaskDraft
}

struct MockTaskParsingService: TaskParsingService {
    func parse(input: TaskParseInput) async throws -> ParsedTaskDraft {
        AppLog.aiParse.info("parse_started provider=mock textLength=\(input.text.count, privacy: .public) timeZone=\(input.timeZoneIdentifier, privacy: .public)")
        try await Task.sleep(for: .milliseconds(250))

        let deadline = Calendar.current.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: Calendar.current.date(byAdding: .day, value: 1, to: input.capturedAt) ?? input.capturedAt
        )

        AppLog.aiParse.info("parse_completed provider=mock sourceChannel=feishu deadline=\(deadline?.ISO8601Format() ?? "nil", privacy: .public) confidence=0.86")

        return ParsedTaskDraft(
            title: "让李四确认发布 checklist",
            originalText: input.text,
            sourceChannel: .feishu,
            assignee: "李四",
            deadline: deadline,
            confidence: 0.86,
            needsReview: false
        )
    }
}

struct CloudLLMTaskParsingService: TaskParsingService {
    func parse(input: TaskParseInput) async throws -> ParsedTaskDraft {
        // 后续接入云端 LLM 时，必须使用严格 JSON Schema，并把 parseBaseDate/timeZone 传入提示词以硬化相对时间。
        AppLog.aiParse.error("parse_skipped provider=cloud_llm reason=not_configured textLength=\(input.text.count, privacy: .public) retryable=false")
        throw TaskParsingError.providerNotConfigured
    }
}

enum TaskParsingError: LocalizedError {
    case providerNotConfigured
    case invalidEndpoint
    case emptyModelOutput
    case invalidModelJSON
    case providerError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "AI 解析服务尚未配置"
        case .invalidEndpoint:
            return "AI 解析服务地址无效"
        case .emptyModelOutput:
            return "AI 没有返回解析结果"
        case .invalidModelJSON:
            return "AI 返回的 JSON 无法解析"
        case let .providerError(statusCode, body):
            return "AI 服务请求失败：HTTP \(statusCode) \(body)"
        }
    }
}

struct OpenAICompatibleTaskParsingService: TaskParsingService {
    let baseURL: String
    let apiKey: String
    let model: String

    func parse(input: TaskParseInput) async throws -> ParsedTaskDraft {
        guard let endpoint = chatCompletionsURL() else {
            throw TaskParsingError.invalidEndpoint
        }

        AppLog.aiParse.info("parse_started provider=openai_compatible model=\(model, privacy: .public) textLength=\(input.text.count, privacy: .public) timeZone=\(input.timeZoneIdentifier, privacy: .public)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: [
                    .init(role: "system", content: Self.systemPrompt),
                    .init(role: "user", content: userPrompt(input: input))
                ],
                temperature: 0.1,
                responseFormat: .init(type: "json_object")
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLog.aiParse.error("parse_failed provider=openai_compatible model=\(model, privacy: .public) statusCode=\(httpResponse.statusCode, privacy: .public)")
            throw TaskParsingError.providerError(statusCode: httpResponse.statusCode, body: body)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw TaskParsingError.emptyModelOutput
        }

        let jsonContent = Self.stripMarkdownFence(content)
        guard let payloadData = jsonContent.data(using: .utf8) else {
            throw TaskParsingError.invalidModelJSON
        }

        let payload = try JSONDecoder().decode(ParsedTaskPayload.self, from: payloadData)
        let deadline = payload.deadline.flatMap(Self.parseDate)
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)

        AppLog.aiParse.info("parse_completed provider=openai_compatible model=\(model, privacy: .public) sourceChannel=\(payload.sourceChannel ?? "unknown", privacy: .public) deadline=\(deadline?.ISO8601Format() ?? "nil", privacy: .public) confidence=\(payload.confidence ?? -1, privacy: .public)")

        return ParsedTaskDraft(
            title: title.isEmpty ? String(input.text.prefix(28)) : title,
            originalText: input.text,
            sourceChannel: SourceChannel(rawValue: payload.sourceChannel ?? "") ?? .unknown,
            assignee: payload.assignee,
            deadline: deadline,
            confidence: payload.confidence ?? 0.5,
            needsReview: payload.needsReview ?? true
        )
    }

    private func chatCompletionsURL() -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            return nil
        }

        if components.path.hasSuffix("/chat/completions") {
            return components.url
        }

        components.path = (components.path as NSString).appendingPathComponent("chat/completions")
        return components.url
    }

    private func userPrompt(input: TaskParseInput) -> String {
        """
        当前时间：\(input.capturedAt.ISO8601Format())
        当前时区：\(input.timeZoneIdentifier)
        当前语言环境：\(input.localeIdentifier)

        原始输入：
        \(input.text)
        """
    }

    private static let systemPrompt = """
    你是 MindAnchor 的任务解析器。请只输出一个 JSON 对象，不要输出 Markdown。
    目标：把中文/中英混杂口语输入解析为任务草稿。
    要求：
    - title：精简任务标题，去掉“呃、那个、记得”等口头填充。
    - sourceChannel：只能是 unknown、faceToFace、dingtalk、feishu。
    - assignee：相关人，没有则为 null。
    - deadline：如果能判断截止时间，输出 ISO-8601 日期时间字符串；必须基于用户给出的当前时间和时区硬化“明天中午、周五下班前”等相对时间。不能判断则为 null。
    - confidence：0 到 1。
    - needsReview：时间、相关人或来源不确定时为 true。
    JSON Schema：
    {"title":"string","sourceChannel":"unknown|faceToFace|dingtalk|feishu","assignee":null,"deadline":null,"confidence":0.0,"needsReview":true}
    """

    private static func stripMarkdownFence(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: trimmed)
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct ParsedTaskPayload: Decodable {
    let title: String
    let sourceChannel: String?
    let assignee: String?
    let deadline: String?
    let confidence: Double?
    let needsReview: Bool?
}

enum NetworkServiceError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务返回无效响应"
        case let .httpStatus(status, body):
            return "服务请求失败：HTTP \(status) \(body)"
        }
    }
}
