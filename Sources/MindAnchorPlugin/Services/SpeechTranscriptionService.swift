import CryptoKit
import Foundation

protocol SpeechTranscriptionService: Sendable {
    func transcribe(audioFile: URL?, context: TranscriptionContext) async throws -> TranscriptionResult
}

struct MockTranscriptionService: SpeechTranscriptionService {
    func transcribe(audioFile: URL?, context: TranscriptionContext) async throws -> TranscriptionResult {
        AppLog.stt.info("transcription_started processId=\(context.processId.uuidString, privacy: .public) provider=mock platform=\(context.platform, privacy: .public) maxDurationSeconds=\(context.maxDurationSeconds, privacy: .public)")
        try await Task.sleep(for: .milliseconds(250))

        return TranscriptionResult(
            text: "记得明天中午前让李四确认飞书里的发布 checklist，完成后同步给产品群。",
            durationMilliseconds: 1200,
            provider: "mock"
        )
    }
}

struct TencentShortASRService: SpeechTranscriptionService {
    let secretId: String
    let secretKey: String
    let engine: String
    let region: String

    init(secretId: String, secretKey: String, engine: String, region: String = "ap-shanghai") {
        self.secretId = secretId
        self.secretKey = secretKey
        self.engine = engine
        self.region = region
    }

    func transcribe(audioFile: URL?, context: TranscriptionContext) async throws -> TranscriptionResult {
        guard let audioFile else {
            throw TranscriptionError.missingAudioFile
        }

        let startedAt = Date()
        let audioData = try Data(contentsOf: audioFile)
        guard !audioData.isEmpty else {
            throw TranscriptionError.emptyAudioFile
        }

        // 腾讯云一句话识别限制短音频；MVP 在客户端先做大小保护，避免上传明显不可用的录音。
        guard audioData.count <= 3 * 1024 * 1024 else {
            AppLog.stt.error("transcription_rejected processId=\(context.processId.uuidString, privacy: .public) provider=tencent reason=audio_too_large bytes=\(audioData.count, privacy: .public)")
            throw TranscriptionError.audioTooLarge(bytes: audioData.count)
        }

        AppLog.stt.info("transcription_started processId=\(context.processId.uuidString, privacy: .public) provider=tencent platform=\(context.platform, privacy: .public) bytes=\(audioData.count, privacy: .public) engine=\(engine, privacy: .public)")

        let requestBody = TencentSentenceRecognitionRequest(
            projectId: 0,
            subServiceType: 2,
            engSerViceType: engine,
            sourceType: 1,
            voiceFormat: audioFile.pathExtension.isEmpty ? "m4a" : audioFile.pathExtension.lowercased(),
            usrAudioKey: context.processId.uuidString,
            data: audioData.base64EncodedString(),
            dataLen: audioData.count
        )
        let body = try JSONEncoder().encode(requestBody)
        let response: TencentSentenceRecognitionResponse = try await TencentCloudClient(
            secretId: secretId,
            secretKey: secretKey,
            region: region,
            service: "asr",
            host: "asr.tencentcloudapi.com"
        )
        .send(action: "SentenceRecognition", version: "2019-06-14", body: body)

        if let error = response.response.error {
            AppLog.stt.error("transcription_failed processId=\(context.processId.uuidString, privacy: .public) provider=tencent requestId=\(response.response.requestId ?? "unknown", privacy: .public) errorCode=\(error.code, privacy: .public)")
            throw TranscriptionError.providerError(provider: "tencent", code: error.code, message: error.message)
        }

        let result = response.response.result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.isEmpty else {
            throw TranscriptionError.emptyResult(provider: "tencent")
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return TranscriptionResult(text: result, durationMilliseconds: durationMs, provider: "tencent")
    }
}

struct SenseVoiceLocalTranscriptionService: SpeechTranscriptionService {
    let repoPath: String
    let pythonPath: String
    let modelName: String
    let device: String
    let language: String
    let port: Int

    func transcribe(audioFile: URL?, context: TranscriptionContext) async throws -> TranscriptionResult {
        guard let audioFile else {
            throw TranscriptionError.missingAudioFile
        }

        let startedAt = Date()
        let trimmedRepoPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPythonPath = pythonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepoPath.isEmpty, FileManager.default.fileExists(atPath: trimmedRepoPath) else {
            AppLog.stt.error("transcription_configuration_missing provider=sensevoice reason=repo_path_invalid processId=\(context.processId.uuidString, privacy: .public)")
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        let usesManagedPython = trimmedPythonPath == SenseVoiceDefaults.managedPythonURL.path
        guard usesManagedPython || FileManager.default.isExecutableFile(atPath: trimmedPythonPath) else {
            AppLog.stt.error("transcription_configuration_missing provider=sensevoice reason=python_path_invalid processId=\(context.processId.uuidString, privacy: .public)")
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        AppLog.stt.info("transcription_started processId=\(context.processId.uuidString, privacy: .public) provider=sensevoice platform=\(context.platform, privacy: .public) repoPathConfigured=\(!trimmedRepoPath.isEmpty, privacy: .public) model=\(modelName, privacy: .public) device=\(device, privacy: .public) language=\(language, privacy: .public)")

        let configuration = SenseVoiceServiceConfiguration(
            repoPath: trimmedRepoPath,
            pythonPath: trimmedPythonPath,
            modelName: modelName,
            device: device,
            port: port
        )
        try await SenseVoiceServiceManager.shared.ensureRunning(configuration: configuration)

        let text = try await requestTranscription(audioFile: audioFile, port: configuration.port)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.emptyResult(provider: "sensevoice")
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLog.stt.info("transcription_completed processId=\(context.processId.uuidString, privacy: .public) provider=sensevoice transcriptLength=\(text.count, privacy: .public) durationMs=\(durationMs, privacy: .public)")
        return TranscriptionResult(text: text, durationMilliseconds: durationMs, provider: "sensevoice")
    }

    private func requestTranscription(audioFile: URL, port: Int) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/v1/asr") else {
            throw TranscriptionError.invalidLocalProviderOutput(provider: "sensevoice")
        }

        let boundary = "MindAnchorBoundary-\(UUID().uuidString)"
        let body = try multipartBody(audioFile: audioFile, boundary: boundary)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(SenseVoiceAPIResponse.self, from: data)
        return decoded.result.map(\.text).joined(separator: "\n")
    }

    private func multipartBody(audioFile: URL, boundary: String) throws -> Data {
        var body = Data()
        let filename = audioFile.lastPathComponent
        let audioData = try Data(contentsOf: audioFile)

        appendField(name: "keys", value: filename, boundary: boundary, to: &body)
        appendField(name: "lang", value: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : language, boundary: boundary, to: &body)
        appendField(name: "use_itn", value: "true", boundary: boundary, to: &body)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func appendField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    private struct SenseVoiceAPIResponse: Decodable {
        let result: [Item]

        struct Item: Decodable {
            let text: String
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

enum TranscriptionError: LocalizedError {
    case providerNotConfigured(provider: String)
    case missingAudioFile
    case emptyAudioFile
    case audioTooLarge(bytes: Int)
    case emptyResult(provider: String)
    case providerError(provider: String, code: String, message: String)
    case localProviderFailed(provider: String, exitCode: Int32, output: String)
    case invalidLocalProviderOutput(provider: String)

    var errorDescription: String? {
        switch self {
        case let .providerNotConfigured(provider):
            return "\(provider) STT 尚未配置"
        case .missingAudioFile:
            return "缺少待转写音频"
        case .emptyAudioFile:
            return "录音文件为空"
        case let .audioTooLarge(bytes):
            return "录音文件过大：\(bytes) 字节"
        case let .emptyResult(provider):
            return "\(provider) 没有返回转写文本"
        case let .providerError(provider, code, message):
            return "\(provider) 转写失败：\(code) \(message)"
        case let .localProviderFailed(provider, exitCode, output):
            return "\(provider) 本地转写失败：退出码 \(exitCode)。\(output)"
        case let .invalidLocalProviderOutput(provider):
            return "\(provider) 本地转写输出格式无效"
        }
    }
}

private struct TencentSentenceRecognitionRequest: Encodable {
    let projectId: Int
    let subServiceType: Int
    let engSerViceType: String
    let sourceType: Int
    let voiceFormat: String
    let usrAudioKey: String
    let data: String
    let dataLen: Int

    enum CodingKeys: String, CodingKey {
        case projectId = "ProjectId"
        case subServiceType = "SubServiceType"
        case engSerViceType = "EngSerViceType"
        case sourceType = "SourceType"
        case voiceFormat = "VoiceFormat"
        case usrAudioKey = "UsrAudioKey"
        case data = "Data"
        case dataLen = "DataLen"
    }
}

private struct TencentSentenceRecognitionResponse: Decodable {
    let response: Response

    enum CodingKeys: String, CodingKey {
        case response = "Response"
    }

    struct Response: Decodable {
        let result: String?
        let requestId: String?
        let error: APIError?

        enum CodingKeys: String, CodingKey {
            case result = "Result"
            case requestId = "RequestId"
            case error = "Error"
        }
    }

    struct APIError: Decodable {
        let code: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case message = "Message"
        }
    }
}

private struct TencentCloudClient {
    let secretId: String
    let secretKey: String
    let region: String
    let service: String
    let host: String

    func send<Response: Decodable>(action: String, version: String, body: Data) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://\(host)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let timestamp = Int(Date().timeIntervalSince1970)
        let authorization = authorizationHeader(action: action, version: version, timestamp: timestamp, body: body)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func authorizationHeader(action: String, version: String, timestamp: Int, body: Data) -> String {
        let algorithm = "TC3-HMAC-SHA256"
        let date = utcDateString(timestamp: timestamp)
        let credentialScope = "\(date)/\(service)/tc3_request"
        let signedHeaders = "content-type;host"
        let hashedPayload = SHA256.hash(data: body).hexString
        let canonicalRequest = [
            "POST",
            "/",
            "",
            "content-type:application/json; charset=utf-8\nhost:\(host)\n",
            signedHeaders,
            hashedPayload
        ].joined(separator: "\n")

        let hashedCanonicalRequest = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        let stringToSign = [
            algorithm,
            String(timestamp),
            credentialScope,
            hashedCanonicalRequest
        ].joined(separator: "\n")

        let secretDate = hmacSHA256(key: Data("TC3\(secretKey)".utf8), message: date)
        let secretService = hmacSHA256(key: secretDate, message: service)
        let secretSigning = hmacSHA256(key: secretService, message: "tc3_request")
        let signature = hmacSHA256(key: secretSigning, message: stringToSign).hexString

        return "\(algorithm) Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private func hmacSHA256(key: Data, message: String) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return Data(signature)
    }

    private func utcDateString(timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
