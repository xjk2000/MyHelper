import Foundation

struct GLProject: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let instanceId: UUID
    let pathWithNamespace: String
    let name: String
    let httpUrlToRepo: URL
    let sshUrlToRepo: URL
    let defaultBranch: String?
    let lastActivityAt: Date?
    let webURL: URL
}
