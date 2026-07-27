import Foundation

/// GitLab REST v4 返回的 project JSON
struct ProjectDTO: Decodable {
    let id: Int
    let name: String
    let path_with_namespace: String
    let http_url_to_repo: URL
    let ssh_url_to_repo: URL
    let default_branch: String?
    let last_activity_at: Date?
    let web_url: URL

    func toModel(instanceId: UUID) -> GLProject {
        GLProject(
            id: id,
            instanceId: instanceId,
            pathWithNamespace: path_with_namespace,
            name: name,
            httpUrlToRepo: http_url_to_repo,
            sshUrlToRepo: ssh_url_to_repo,
            defaultBranch: default_branch,
            lastActivityAt: last_activity_at,
            webURL: web_url
        )
    }
}

struct UserDTO: Decodable {
    let id: Int
    let username: String
    let name: String
}

struct PipelineDTO: Decodable {
    let id: Int?
    let ref: String?
    let status: String
    let web_url: URL?
    let created_at: Date?
    let updated_at: Date?
    let started_at: Date?
    let finished_at: Date?
    let duration: Int?

    func toModel(fallbackRef: String? = nil) -> PipelineResult {
        PipelineResult(
            status: PipelineStatus(rawValue: status) ?? .unknown,
            webURL: web_url,
            updatedAt: updated_at,
            startedAt: started_at ?? created_at ?? updated_at,
            ref: ref ?? fallbackRef
        )
    }
}

struct BranchDTO: Decodable {
    let name: String
}

struct GLBranch: Identifiable, Equatable {
    var id: String { name }
    let name: String
}
