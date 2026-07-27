import Foundation

struct BranchResolver {
    let branchProvider: (Int, String?) async throws -> [GLBranch]

    func resolve(selector: BranchSelector, projectId: Int) async throws -> String? {
        switch selector {
        case .fixed(let branch):
            return branch
        case .rule, .regex:
            guard let pattern = selector.compiledRegex else { return nil }
            let regex = try NSRegularExpression(pattern: pattern)
            let search = selector.searchPrefix.map { "^\($0)" }
            let branches = try await branchProvider(projectId, search)
            return branches
                .map(\.name)
                .filter { name in
                    let range = NSRange(name.startIndex..<name.endIndex, in: name)
                    return regex.firstMatch(in: name, range: range) != nil
                }
                .sorted(by: >)
                .first
        }
    }
}
