import Foundation

final class GitRunner: GitRunning, @unchecked Sendable {
    private let gitPath: String

    init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    func run(_ args: [String], cwd: URL?, output: GitOutputCallback?) async throws -> GitResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                let finish = ContinuationBox(cont)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = args
                if let cwd { process.currentDirectoryURL = cwd }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GIT_PROGRESS_DELAY"] = "0"
                process.environment = env

                let outBuffer = OutputBuffer()
                let errBuffer = OutputBuffer()

                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        outBuffer.append(data)
                        outputData(data, stream: .stdout, output: output)
                    }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        errBuffer.append(data)
                        outputData(data, stream: .stderr, output: output)
                    }
                }

                process.terminationHandler = { proc in
                    box.clear()
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    if let rest = try? outPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
                        outBuffer.append(rest)
                        outputData(rest, stream: .stdout, output: output)
                    }
                    if let rest = try? errPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
                        errBuffer.append(rest)
                        outputData(rest, stream: .stderr, output: output)
                    }
                    if box.wasCancelled {
                        finish.resume(throwing: CancellationError())
                        return
                    }
                    let out = String(data: outBuffer.snapshot(), encoding: .utf8) ?? ""
                    let err = String(data: errBuffer.snapshot(), encoding: .utf8) ?? ""
                    finish.resume(returning: GitResult(
                        exitCode: proc.terminationStatus,
                        stdout: out,
                        stderr: err
                    ))
                }

                do {
                    box.set(process)
                    try process.run()
                    if Task.isCancelled {
                        process.terminate()
                    }
                } catch {
                    box.clear()
                    process.terminationHandler = nil
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    finish.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

private func outputData(_ data: Data, stream: GitOutputStream, output: GitOutputCallback?) {
    guard let output, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
    for line in text.split(whereSeparator: \.isNewline) {
        output(GitOutput(projectId: nil, stream: stream, message: String(line)))
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var continuation: CheckedContinuation<GitResult, Error>?

    init(_ continuation: CheckedContinuation<GitResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: GitResult) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}

/// 线程安全的 Data 累积容器(readabilityHandler 在内部队列回调,需要锁)
private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ d: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(d)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
