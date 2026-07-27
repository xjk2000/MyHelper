import Foundation
import Observation

@Observable
@MainActor
final class ProjectListViewModel {
    var searchText: String = ""
    var selectedIds: Set<Int> = []
    var mode: CloneMode = .pull

    func displayed(all: [GLProject]) -> [GLProject] {
        let t = searchText.lowercased()
        if t.isEmpty { return all }
        return all.filter {
            $0.pathWithNamespace.lowercased().contains(t)
                || $0.name.lowercased().contains(t)
        }
    }

    func toggleAll(in projects: [GLProject]) {
        let all = Set(projects.map(\.id))
        if selectedIds.isSuperset(of: all) {
            selectedIds.subtract(all)
        } else {
            selectedIds.formUnion(all)
        }
    }
}
