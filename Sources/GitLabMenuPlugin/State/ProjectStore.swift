import Foundation
import Observation

@Observable
final class ProjectStore {
    /// instanceId -> projects
    var projects: [UUID: [GLProject]] = [:]
    /// instanceId -> loading?
    var loading: [UUID: Bool] = [:]
    /// instanceId -> last error
    var lastError: [UUID: String] = [:]

    func projects(for instanceId: UUID) -> [GLProject] {
        projects[instanceId] ?? []
    }

    @MainActor
    func reload(instance: GitLabInstance, token: String) async {
        loading[instance.id] = true
        lastError[instance.id] = nil
        do {
            let client = GitLabClient(instance: instance, token: token)
            let list = try await client.listMyProjects()
            projects[instance.id] = list
        } catch {
            lastError[instance.id] = error.localizedDescription
        }
        loading[instance.id] = false
    }
}
