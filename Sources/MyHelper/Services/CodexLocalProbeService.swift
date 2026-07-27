import Foundation

enum CodexLocalProbeStatus: String, Codable, Equatable {
    case healthy
    case unstable
    case degraded
    case failed
}

struct CodexLocalProbeTaskResult: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let category: String
    let score: Double
    let passed: Bool
    let durationSeconds: Double
    let summary: String
}

struct CodexLocalProbeSnapshot: Codable, Equatable {
    let ranAt: Date
    let score: Double
    let status: CodexLocalProbeStatus
    let durationSeconds: Double
    let passedTasks: Int
    let totalTasks: Int
    let taskResults: [CodexLocalProbeTaskResult]
    let benchmarkSources: [CodexProbeBenchmarkSource]
    let errorMessage: String?
}

struct CodexProbeBenchmarkSource: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: String
}

enum CodexLocalProbeError: LocalizedError {
    case codexNotFound
    case processFailed(String)
    case timedOut
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未找到 codex CLI"
        case let .processFailed(message):
            return message.isEmpty ? "Codex 探针执行失败" : message
        case .timedOut:
            return "Codex 探针执行超时"
        case .invalidJSON:
            return "Codex 探针没有返回有效 JSON"
        }
    }
}

struct CodexLocalProbeService {
    private let timeoutSeconds: TimeInterval = 90

    static let benchmarkSources: [CodexProbeBenchmarkSource] = [
        CodexProbeBenchmarkSource(
            id: "humaneval",
            title: "HumanEval：代码生成/单元测试题型",
            url: "https://github.com/openai/human-eval"
        ),
        CodexProbeBenchmarkSource(
            id: "mbpp",
            title: "MBPP：短程序合成题型",
            url: "https://github.com/google-research/google-research/tree/master/mbpp"
        ),
        CodexProbeBenchmarkSource(
            id: "ifeval",
            title: "IFEval：可验证指令遵循题型",
            url: "https://github.com/google-research/google-research/tree/master/instruction_following_eval"
        ),
        CodexProbeBenchmarkSource(
            id: "gsm8k",
            title: "GSM8K：多步算术推理题型",
            url: "https://github.com/openai/grade-school-math"
        )
    ]

    static func loadLastSnapshot() -> CodexLocalProbeSnapshot? {
        guard let data = try? Data(contentsOf: latestSnapshotURL) else { return nil }
        return try? JSONDecoder.probeDecoder.decode(CodexLocalProbeSnapshot.self, from: data)
    }

    func run() async -> CodexLocalProbeSnapshot {
        do {
            let startedAt = Date()
            let tasks = Self.probeTasks
            let response = try await runCodex(prompt: Self.prompt(for: tasks))
            let taskResults = try Self.evaluate(response: response, tasks: tasks)
            let duration = Date().timeIntervalSince(startedAt)
            let score = taskResults.isEmpty
                ? 0
                : taskResults.map(\.score).reduce(0, +) / Double(taskResults.count)
            let snapshot = CodexLocalProbeSnapshot(
                ranAt: Date(),
                score: score,
                status: Self.status(for: score, failed: false),
                durationSeconds: duration,
                passedTasks: taskResults.filter(\.passed).count,
                totalTasks: taskResults.count,
                taskResults: taskResults,
                benchmarkSources: Self.benchmarkSources,
                errorMessage: nil
            )
            Self.persist(snapshot)
            return snapshot
        } catch {
            let snapshot = CodexLocalProbeSnapshot(
                ranAt: Date(),
                score: 0,
                status: .failed,
                durationSeconds: 0,
                passedTasks: 0,
                totalTasks: Self.probeTasks.count,
                taskResults: [],
                benchmarkSources: Self.benchmarkSources,
                errorMessage: error.localizedDescription
            )
            Self.persist(snapshot)
            return snapshot
        }
    }

    private func runCodex(prompt: String) async throws -> String {
        guard let codexPath = Self.codexExecutablePath() else {
            throw CodexLocalProbeError.codexNotFound
        }

        let outputURL = Self.storageDirectory
            .appendingPathComponent("last-message-\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(
            at: Self.storageDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--color", "never",
            "-s", "read-only",
            "-o", outputURL.path,
            "-"
        ]

        let input = Pipe()
        let errorPipe = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        process.currentDirectoryURL = Self.storageDirectory

        do {
            try process.run()
        } catch {
            throw CodexLocalProbeError.processFailed(error.localizedDescription)
        }

        input.fileHandleForWriting.write(Data(prompt.utf8))
        try? input.fileHandleForWriting.close()

        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    return true
                }
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if timedOut {
            throw CodexLocalProbeError.timedOut
        }

        let errorText = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw CodexLocalProbeError.processFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: outputURL)
        return output
    }

    private static func evaluate(
        response: String,
        tasks: [CodexProbeTask]
    ) throws -> [CodexLocalProbeTaskResult] {
        guard let data = extractJSONObject(from: response).data(using: .utf8) else {
            throw CodexLocalProbeError.invalidJSON
        }
        let payload = try JSONDecoder().decode(CodexProbeResponse.self, from: data)

        return tasks.map { task in
            let answer = payload.results.first { $0.id == task.id }
            let score = task.score(answer)
            return CodexLocalProbeTaskResult(
                id: task.id,
                title: task.title,
                category: task.category,
                score: score,
                passed: score >= 80,
                durationSeconds: 0,
                summary: answer?.summary ?? "未返回该题结果"
            )
        }
    }

    private static func status(for score: Double, failed: Bool) -> CodexLocalProbeStatus {
        if failed { return .failed }
        if score >= 85 { return .healthy }
        if score >= 65 { return .unstable }
        return .degraded
    }

    private static func persist(_ snapshot: CodexLocalProbeSnapshot) {
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.probeEncoder.encode(snapshot)
            try data.write(to: latestSnapshotURL, options: .atomic)
        } catch {
            // 探针结果是辅助信息，保存失败不应该影响主界面可用性。
        }
    }

    private static func codexExecutablePath() -> String? {
        [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static var storageDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyHelper", isDirectory: true)
            .appendingPathComponent("ModelProbe", isDirectory: true)
    }

    private static var latestSnapshotURL: URL {
        storageDirectory.appendingPathComponent("codex-local-probe-latest.json")
    }
}

private struct CodexProbeTask {
    let id: String
    let title: String
    let category: String
    let prompt: String
    let score: (CodexProbeAnswer?) -> Double
}

private struct CodexProbeResponse: Decodable {
    let results: [CodexProbeAnswer]
}

private struct CodexProbeAnswer: Decodable {
    let id: String
    let summary: String?
    let answer: String?
    let code: String?
    let json: [String: String]?
}

private extension CodexLocalProbeService {
    static let probeTasks: [CodexProbeTask] = [
        CodexProbeTask(
            id: "json-repair",
            title: "JSON 修复",
            category: "格式遵守",
            prompt: """
            修复这个 JSON，并只在 json 字段中返回紧凑 JSON 字符串：
            {name:"MyHelper", enabled:true, tools:["json","probe",], meta:{score: 98,}}
            """,
            score: { answer in
                guard let raw = answer?.json?["value"] ?? answer?.answer,
                      let data = raw.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["name"] as? String == "MyHelper",
                      object["enabled"] as? Bool == true,
                      let tools = object["tools"] as? [String],
                      tools == ["json", "probe"],
                      let meta = object["meta"] as? [String: Any],
                      (meta["score"] as? NSNumber)?.intValue == 98
                else {
                    return 0
                }
                return 100
            }
        ),
        CodexProbeTask(
            id: "code-synthesis",
            title: "短代码生成",
            category: "代码能力",
            prompt: """
            写一个 Swift 函数签名为 `func stableUnique(_ values: [String]) -> [String]`。
            要求去重但保留第一次出现顺序。只在 code 字段返回函数代码。
            """,
            score: { answer in
                let code = answer?.code ?? answer?.answer ?? ""
                var score = 0.0
                if code.contains("func stableUnique") { score += 25 }
                if code.contains("Set<String>") || code.contains("Set<") { score += 25 }
                if code.contains("append") { score += 20 }
                if code.contains("insert") { score += 20 }
                if !code.contains(".sorted") { score += 10 }
                return min(score, 100)
            }
        ),
        CodexProbeTask(
            id: "instruction-following",
            title: "约束遵循",
            category: "指令遵循",
            prompt: """
            生成 3 个中文短标签。必须全部以“本机”开头，每个标签 4 个汉字，不能出现标点。
            只在 json 字段返回：{"items":"标签1|标签2|标签3"}
            """,
            score: { answer in
                guard let raw = answer?.json?["items"] ?? answer?.answer else { return 0 }
                let items = raw.split(separator: "|").map(String.init)
                guard items.count == 3 else { return 20 }
                let validCount = items.filter { item in
                    item.hasPrefix("本机")
                        && item.count == 4
                        && item.range(of: #"^\p{Han}{4}$"#, options: .regularExpression) != nil
                }.count
                return Double(validCount) / 3.0 * 100
            }
        ),
        CodexProbeTask(
            id: "reasoning",
            title: "多步推理",
            category: "推理",
            prompt: """
            从 09:10 开始每 4 分钟调用一次接口，到 09:50 结束，包含 09:10 和 09:50 两端，一共会触发多少次调用？
            只在 answer 字段返回最终数字，不要解释。
            """,
            score: { answer in
                let value = (answer?.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value == "11" ? 100 : 0
            }
        )
    ]

    static func prompt(for tasks: [CodexProbeTask]) -> String {
        """
        你正在接受 MyHelper 的本机 Codex 能力探针。请独立完成下列小任务。
        输出必须是一个 JSON 对象，不要 Markdown，不要代码块，不要额外解释。
        顶层格式必须是：
        {"results":[{"id":"任务ID","summary":"一句话说明","answer":"文本答案","code":"代码答案","json":{"value":"JSON字符串或其它键值"}}]}

        任务：
        \(tasks.map { "- \($0.id)｜\($0.title)：\($0.prompt)" }.joined(separator: "\n\n"))
        """
    }

    static func extractJSONObject(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start < end
        else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

private extension JSONEncoder {
    static var probeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var probeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
