import Foundation

enum LocalRepoChecker {
    /// 判断 root/pathWithNamespace/.git 是否存在
    static func isCloned(rootDirectory: URL, pathWithNamespace: String) -> Bool {
        gitDirectory(rootDirectory: rootDirectory, pathWithNamespace: pathWithNamespace) != nil
    }

    static func currentBranch(rootDirectory: URL, pathWithNamespace: String) -> String? {
        guard let gitDirectory = gitDirectory(rootDirectory: rootDirectory, pathWithNamespace: pathWithNamespace) else {
            return nil
        }
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard let rawHead = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawHead.isEmpty else {
            return nil
        }
        let refPrefix = "ref: refs/heads/"
        if rawHead.hasPrefix(refPrefix) {
            return String(rawHead.dropFirst(refPrefix.count))
        }
        return "detached \(String(rawHead.prefix(7)))"
    }

    private static func gitDirectory(rootDirectory: URL, pathWithNamespace: String) -> URL? {
        let repoDirectory = rootDirectory.appendingPathComponent(pathWithNamespace)
        let dotGitURL = repoDirectory.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGitURL
        }
        guard let contents = try? String(contentsOf: dotGitURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            contents.hasPrefix("gitdir:") else {
            return nil
        }
        let rawPath = contents.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirectory: URL
        if rawPath.hasPrefix("/") {
            gitDirectory = URL(fileURLWithPath: rawPath)
        } else {
            gitDirectory = repoDirectory.appendingPathComponent(rawPath)
        }
        var targetIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDirectory.path, isDirectory: &targetIsDirectory),
              targetIsDirectory.boolValue else {
            return nil
        }
        return gitDirectory
    }
}
