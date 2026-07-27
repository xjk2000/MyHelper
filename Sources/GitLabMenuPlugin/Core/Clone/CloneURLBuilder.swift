import Foundation

enum CloneURLBuilder {
    /// HTTPS 模式下把 PAT 注入 URL,SSH 直接返回 ssh url
    static func cloneURL(for project: GLProject,
                         protocolKind: CloneProtocol,
                         token: String) -> String {
        switch protocolKind {
        case .ssh:
            return project.sshUrlToRepo.absoluteString
        case .https:
            return injectToken(project.httpUrlToRepo, token: token)
        }
    }

    /// 把 token 注入 https URL: https://oauth2:<token>@host/...
    static func injectToken(_ url: URL, token: String) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme == "https" else { return url.absoluteString }
        comps.user = "oauth2"
        comps.password = token
        return comps.url?.absoluteString ?? url.absoluteString
    }

    /// 擦除 URL 中的 user/password
    static func stripCredentials(_ urlString: String) -> String {
        guard var comps = URLComponents(string: urlString) else { return urlString }
        comps.user = nil
        comps.password = nil
        return comps.url?.absoluteString ?? urlString
    }
}
