import Foundation

enum GitLabError: Error, LocalizedError {
    case invalidURL
    case unauthorized          // 401
    case forbidden             // 403
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int, body: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "无效的 URL"
        case .unauthorized:         return "PAT 失效或权限不足(401)"
        case .forbidden:            return "无权限访问(403)"
        case .rateLimited:          return "触发 GitLab 限流"
        case .httpStatus(let c, _): return "HTTP \(c)"
        case .decoding(let e):      return "解析失败: \(e.localizedDescription)"
        case .transport(let e):     return "网络错误: \(e.localizedDescription)"
        }
    }
}
