import Foundation

enum GitOutputStream: Sendable, Equatable {
    case stdout
    case stderr
}

struct GitOutput: Sendable, Equatable {
    let projectId: Int?
    let stream: GitOutputStream
    let message: String
}

typealias GitOutputCallback = @Sendable (GitOutput) -> Void

struct GitResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var succeeded: Bool { exitCode == 0 }
}

protocol GitRunning: Sendable {
    func run(_ args: [String], cwd: URL?, output: GitOutputCallback?) async throws -> GitResult
}

extension GitRunning {
    func run(_ args: [String], cwd: URL?) async throws -> GitResult {
        try await run(args, cwd: cwd, output: nil)
    }
}
