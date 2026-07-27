import Foundation

struct RetryPolicy {
    var maxAttempts: Int = 3
    var baseDelayMs: Int = 200   // 退避起点;实际 = base * 2^(attempt-1)

    static let `default` = RetryPolicy()
}

actor GitLabClient {
    let instance: GitLabInstance
    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let retryPolicy: RetryPolicy

    init(instance: GitLabInstance,
         token: String,
         session: URLSession = .shared,
         retryPolicy: RetryPolicy = .default) {
        self.instance = instance
        self.token = token
        self.session = session
        self.retryPolicy = retryPolicy
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected GitLab ISO8601 date string."
            )
        }
        self.decoder = d
    }

    // MARK: - Public API

    func verifyToken() async throws -> UserDTO {
        let url = apiURL(path: "user")
        let (data, _) = try await sendWithRetry(makeRequest(url: url))
        do { return try decoder.decode(UserDTO.self, from: data) }
        catch { throw GitLabError.decoding(error) }
    }

    func listMyProjects() async throws -> [GLProject] {
        let firstURL = apiURL(path: "projects", query: [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc")
        ])
        let dtos: [ProjectDTO] = try await fetchAllPages(starting: firstURL)
        return dtos.map { $0.toModel(instanceId: instance.id) }
    }

    func latestPipeline(projectId: Int, branch: String) async throws -> PipelineResult {
        let url = apiURL(path: "projects/\(projectId)/pipelines", query: [
            URLQueryItem(name: "ref", value: branch),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "order_by", value: "id"),
            URLQueryItem(name: "sort", value: "desc")
        ])
        let (data, _) = try await sendWithRetry(makeRequest(url: url))
        do {
            let dtos = try decoder.decode([PipelineDTO].self, from: data)
            return dtos.first?.toModel(fallbackRef: branch) ?? PipelineResult(
                status: .unknown,
                webURL: nil,
                updatedAt: nil
            )
        } catch {
            throw GitLabError.decoding(error)
        }
    }

    func currentOrLatestPipeline(projectId: Int, selector: BranchSelector, limit: Int = 100) async throws -> PipelineResult {
        let perPage = max(1, min(limit, 100))
        var query = [
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "order_by", value: "id"),
            URLQueryItem(name: "sort", value: "desc")
        ]
        var fallbackRef: String?
        if case .fixed(let branch) = selector {
            query.insert(URLQueryItem(name: "ref", value: branch), at: 0)
            fallbackRef = branch
        }

        var next: URL? = apiURL(path: "projects/\(projectId)/pipelines", query: query)
        var firstMatching: PipelineDTO?
        while let current = next {
            let (data, http) = try await sendWithRetry(makeRequest(url: current))
            let dtos: [PipelineDTO]
            do {
                dtos = try decoder.decode([PipelineDTO].self, from: data)
            } catch {
                throw GitLabError.decoding(error)
            }

            let matching = try dtos.filter { dto in
                try matchesPipeline(dto, selector: selector, fallbackRef: fallbackRef)
            }
            if let active = matching.first(where: { Self.isActivePipelineStatus($0.status) }) {
                return active.toModel(fallbackRef: fallbackRef)
            }
            if firstMatching == nil {
                firstMatching = matching.first
            }
            next = LinkHeader.nextURL(from: http.value(forHTTPHeaderField: "Link"))
        }

        guard let firstMatching else {
            return PipelineResult(status: .unknown, webURL: nil, updatedAt: nil, ref: fallbackRef)
        }
        return firstMatching.toModel(fallbackRef: fallbackRef)
    }

    func recentSuccessDurations(projectId: Int, branch: String, limit: Int = 5) async throws -> [TimeInterval] {
        let perPage = max(1, min(limit, 20))
        let url = apiURL(path: "projects/\(projectId)/pipelines", query: [
            URLQueryItem(name: "ref", value: branch),
            URLQueryItem(name: "status", value: "success"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "order_by", value: "id"),
            URLQueryItem(name: "sort", value: "desc")
        ])
        let (data, _) = try await sendWithRetry(makeRequest(url: url))
        let dtos: [PipelineDTO]
        do {
            dtos = try decoder.decode([PipelineDTO].self, from: data)
        } catch {
            throw GitLabError.decoding(error)
        }

        return await withTaskGroup(of: TimeInterval?.self) { group in
            for pipeline in dtos {
                guard let id = pipeline.id else { continue }
                group.addTask {
                    await self.pipelineDuration(projectId: projectId, pipelineId: id)
                }
            }
            var durations: [TimeInterval] = []
            for await duration in group {
                if let duration { durations.append(duration) }
            }
            return durations
        }
    }

    func listBranches(projectId: Int, search: String? = nil) async throws -> [GLBranch] {
        var query = [URLQueryItem(name: "per_page", value: "100")]
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        let firstURL = apiURL(path: "projects/\(projectId)/repository/branches", query: query)
        let dtos: [BranchDTO] = try await fetchAllPages(starting: firstURL)
        return dtos.map { GLBranch(name: $0.name) }
    }

    // MARK: - Pagination

    private func fetchAllPages<T: Decodable>(starting url: URL) async throws -> [T] {
        var collected: [T] = []
        var next: URL? = url
        while let current = next {
            let (data, http) = try await sendWithRetry(makeRequest(url: current))
            let page: [T]
            do { page = try decoder.decode([T].self, from: data) }
            catch { throw GitLabError.decoding(error) }
            collected.append(contentsOf: page)
            next = LinkHeader.nextURL(from: http.value(forHTTPHeaderField: "Link"))
        }
        return collected
    }

    // MARK: - Retry

    private func sendWithRetry(_ req: URLRequest) async throws
        -> (Data, HTTPURLResponse)
    {
        var attempt = 0
        var lastError: Error?
        while attempt < retryPolicy.maxAttempts {
            attempt += 1
            do {
                return try await sendOnce(req)
            } catch let err as GitLabError {
                switch err {
                case .unauthorized, .forbidden, .decoding:
                    throw err  // 不重试
                case .rateLimited(let retryAfter):
                    lastError = err
                    let waitMs = Int((retryAfter ?? 1.0) * 1000)
                    try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
                case .transport, .httpStatus, .invalidURL:
                    lastError = err
                    let waitMs = retryPolicy.baseDelayMs * Int(pow(2.0, Double(attempt - 1)))
                    try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
                }
            }
        }
        throw lastError ?? GitLabError.httpStatus(-1, body: nil)
    }

    // MARK: - Low level

    func apiURL(path: String, query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: instance.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = (comps.path.isEmpty ? "" : comps.path) + "/api/v4/\(path)"
        if !query.isEmpty { comps.queryItems = query }
        return comps.url!
    }

    func makeRequest(url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func pipelineDuration(projectId: Int, pipelineId: Int) async -> TimeInterval? {
        let url = apiURL(path: "projects/\(projectId)/pipelines/\(pipelineId)")
        do {
            let (data, _) = try await sendWithRetry(makeRequest(url: url))
            let dto = try decoder.decode(PipelineDTO.self, from: data)
            if let duration = dto.duration, duration > 0 {
                return TimeInterval(duration)
            }
            guard let started = dto.started_at,
                  let finished = dto.finished_at else { return nil }
            let value = finished.timeIntervalSince(started)
            return value > 0 ? value : nil
        } catch {
            return nil
        }
    }

    private func matchesPipeline(_ dto: PipelineDTO, selector: BranchSelector, fallbackRef: String?) throws -> Bool {
        let ref = dto.ref ?? fallbackRef
        switch selector {
        case .fixed(let branch):
            return ref == branch
        case .rule, .regex:
            guard let ref, let pattern = selector.compiledRegex else { return false }
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(ref.startIndex..<ref.endIndex, in: ref)
            return regex.firstMatch(in: ref, range: range) != nil
        }
    }

    private static func isActivePipelineStatus(_ rawStatus: String) -> Bool {
        switch PipelineStatus(rawValue: rawStatus) ?? .unknown {
        case .created, .waitingForResource, .preparing, .pending, .running:
            return true
        case .success, .failed, .canceled, .skipped, .manual, .scheduled, .unknown:
            return false
        }
    }

    func sendOnce(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitLabError.transport(error) }
        guard let http = resp as? HTTPURLResponse else {
            throw GitLabError.httpStatus(-1, body: nil)
        }
        switch http.statusCode {
        case 200...299: return (data, http)
        case 401:       throw GitLabError.unauthorized
        case 403:       throw GitLabError.forbidden
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw GitLabError.rateLimited(retryAfter: retry)
        default:
            let body = String(data: data, encoding: .utf8)
            throw GitLabError.httpStatus(http.statusCode, body: body)
        }
    }
}
