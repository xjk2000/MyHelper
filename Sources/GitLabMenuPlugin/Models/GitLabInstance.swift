import Foundation

struct GitLabInstance: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    var defaultCloneRoot: URL
    var cloneProtocol: CloneProtocol

    static let placeholder = GitLabInstance(
        id: UUID(),
        name: "新实例",
        baseURL: URL(string: "https://gitlab.example.com")!,
        defaultCloneRoot: FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("GitlabRepos"),
        cloneProtocol: .https
    )
}
