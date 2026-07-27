import Foundation

struct SenseVoiceServiceConfiguration: Sendable, Equatable {
    let repoPath: String
    let pythonPath: String
    let modelName: String
    let device: String
    let port: Int
}

actor SenseVoiceServiceManager {
    static let shared = SenseVoiceServiceManager()

    private var process: Process?
    private var activeConfiguration: SenseVoiceServiceConfiguration?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    func ensureRunning(configuration: SenseVoiceServiceConfiguration) async throws {
        let normalized = normalized(configuration)
        let healthy = await isHealthy(port: normalized.port)

        if let process, process.isRunning {
            if activeConfiguration == normalized {
                if healthy {
                    AppLog.stt.info("sensevoice_service_reused pid=\(process.processIdentifier, privacy: .public) port=\(normalized.port, privacy: .public) reason=tracked_process_healthy")
                    return
                }

                try await waitUntilHealthy(port: normalized.port, timeoutSeconds: 90)
                return
            }

            // 配置变化时必须重启当前托管进程，否则模型、设备或路径改动不会真正生效。
            stopCurrentProcess(reason: "configuration_changed")
        } else if healthy {
            activeConfiguration = normalized
            AppLog.stt.info("sensevoice_service_reused port=\(normalized.port, privacy: .public) reason=external_or_previous_process_healthy")
            return
        }

        try await start(configuration: normalized)
        try await waitUntilHealthy(port: normalized.port, timeoutSeconds: 180)
    }

    func stop(reason: String) {
        stopCurrentProcess(reason: reason)
    }

    private func start(configuration: SenseVoiceServiceConfiguration) async throws {
        let configuration = try await prepareRuntimeIfNeeded(configuration)
        guard FileManager.default.fileExists(atPath: configuration.repoPath) else {
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }
        guard FileManager.default.isExecutableFile(atPath: configuration.pythonPath) else {
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.pythonPath)
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.repoPath, isDirectory: true)
        process.arguments = [
            "-c",
            Self.serverBootstrap,
            "--repo", configuration.repoPath,
            "--port", String(configuration.port)
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = [configuration.repoPath, environment["PYTHONPATH"]].compactMap { $0 }.joined(separator: ":")
        environment["SENSEVOICE_DEVICE"] = configuration.device
        environment["SENSEVOICE_MODEL"] = configuration.modelName
        process.environment = environment

        stdoutHandle = logFileHandle(path: "/tmp/mindanchor-sensevoice.stdout.log")
        stderrHandle = logFileHandle(path: "/tmp/mindanchor-sensevoice.stderr.log")
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        self.process = process
        self.activeConfiguration = configuration
        AppLog.stt.info("sensevoice_service_started pid=\(process.processIdentifier, privacy: .public) port=\(configuration.port, privacy: .public) repoConfigured=\(!configuration.repoPath.isEmpty, privacy: .public) device=\(configuration.device, privacy: .public)")
    }

    private func prepareRuntimeIfNeeded(_ configuration: SenseVoiceServiceConfiguration) async throws -> SenseVoiceServiceConfiguration {
        guard FileManager.default.fileExists(atPath: configuration.repoPath) else {
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        if FileManager.default.isExecutableFile(atPath: configuration.pythonPath) {
            return configuration
        }

        guard configuration.pythonPath == SenseVoiceDefaults.managedPythonURL.path else {
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        try await bootstrapManagedRuntime(repoPath: configuration.repoPath)
        guard FileManager.default.isExecutableFile(atPath: configuration.pythonPath) else {
            throw TranscriptionError.providerNotConfigured(provider: "sensevoice")
        }

        return configuration
    }

    private func bootstrapManagedRuntime(repoPath: String) async throws {
        let runtimeDirectory = SenseVoiceDefaults.managedRuntimeDirectoryURL
        let pythonURL = SenseVoiceDefaults.managedPythonURL
        let requirementsURL = URL(fileURLWithPath: repoPath, isDirectory: true).appendingPathComponent("requirements.txt")
        guard FileManager.default.fileExists(atPath: requirementsURL.path) else {
            throw TranscriptionError.localProviderFailed(
                provider: "sensevoice",
                exitCode: -1,
                output: "包内 requirements.txt 缺失：\(requirementsURL.path)"
            )
        }

        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let systemPython = try findSystemPython()
        AppLog.stt.info("sensevoice_runtime_bootstrap_started systemPython=\(systemPython.lastPathComponent, privacy: .public) runtimeDirectory=\(runtimeDirectory.path, privacy: .public)")

        if !FileManager.default.fileExists(atPath: pythonURL.path) {
            try await runProcess(
                executableURL: systemPython,
                arguments: ["-m", "venv", runtimeDirectory.appendingPathComponent(".venv", isDirectory: true).path],
                currentDirectoryURL: runtimeDirectory,
                stage: "create_venv"
            )
        }

        try await runProcess(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            currentDirectoryURL: runtimeDirectory,
            stage: "upgrade_pip"
        )
        try await runProcess(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "-r", requirementsURL.path],
            currentDirectoryURL: runtimeDirectory,
            stage: "install_requirements"
        )

        AppLog.stt.info("sensevoice_runtime_bootstrap_completed pythonPath=\(pythonURL.path, privacy: .public)")
    }

    private func findSystemPython() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["MINDANCHOR_BOOTSTRAP_PYTHON"], FileManager.default.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }

        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: candidate)
        }

        throw TranscriptionError.localProviderFailed(
            provider: "sensevoice",
            exitCode: -1,
            output: "未找到 python3。请先安装 Python 3，或设置 MINDANCHOR_BOOTSTRAP_PYTHON 指向可执行 Python。"
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        stage: String
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        AppLog.stt.info("sensevoice_runtime_command_started stage=\(stage, privacy: .public) executable=\(executableURL.lastPathComponent, privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finishedProcess in
                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let output = String((stdout + "\n" + stderr).suffix(1600))

                if finishedProcess.terminationStatus == 0 {
                    AppLog.stt.info("sensevoice_runtime_command_completed stage=\(stage, privacy: .public)")
                    continuation.resume()
                } else {
                    AppLog.stt.error("sensevoice_runtime_command_failed stage=\(stage, privacy: .public) exitCode=\(finishedProcess.terminationStatus, privacy: .public) output=\(output, privacy: .public)")
                    continuation.resume(throwing: TranscriptionError.localProviderFailed(
                        provider: "sensevoice",
                        exitCode: finishedProcess.terminationStatus,
                        output: output
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func stopCurrentProcess(reason: String) {
        if let process, process.isRunning {
            process.terminate()
            AppLog.stt.info("sensevoice_service_stopped pid=\(process.processIdentifier, privacy: .public) reason=\(reason, privacy: .public)")
        }
        process = nil
        activeConfiguration = nil
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func waitUntilHealthy(port: Int, timeoutSeconds: Int) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if await isHealthy(port: port) {
                AppLog.stt.info("sensevoice_service_ready port=\(port, privacy: .public)")
                return
            }

            if let process, !process.isRunning {
                let stderr = readLogTail(path: "/tmp/mindanchor-sensevoice.stderr.log")
                throw TranscriptionError.localProviderFailed(
                    provider: "sensevoice",
                    exitCode: process.terminationStatus,
                    output: stderr
                )
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw TranscriptionError.localProviderFailed(
            provider: "sensevoice",
            exitCode: -1,
            output: "服务启动超时，请查看 /tmp/mindanchor-sensevoice.stderr.log"
        )
    }

    private func isHealthy(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func normalized(_ configuration: SenseVoiceServiceConfiguration) -> SenseVoiceServiceConfiguration {
        SenseVoiceServiceConfiguration(
            repoPath: configuration.repoPath.trimmingCharacters(in: .whitespacesAndNewlines),
            pythonPath: configuration.pythonPath.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? SenseVoiceDefaults.model : configuration.modelName,
            device: configuration.device.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? SenseVoiceDefaults.device : configuration.device,
            port: configuration.port > 0 ? configuration.port : SenseVoiceDefaults.port
        )
    }

    private func logFileHandle(path: String) -> FileHandle? {
        // 每次启动单独截断日志，设置页展示的错误尾部才不会混入上一次失败原因。
        let url = URL(fileURLWithPath: path)
        try? Data().write(to: url, options: .atomic)
        return FileHandle(forWritingAtPath: path)
    }

    private func readLogTail(path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        return String((String(data: data, encoding: .utf8) ?? "").suffix(1600))
    }

    private static let serverBootstrap = #"""
import argparse
import os
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True)
parser.add_argument("--port", type=int, default=50000)
args = parser.parse_args()

repo = os.path.abspath(args.repo)
sys.path.insert(0, repo)
os.chdir(repo)

import api
import uvicorn

uvicorn.run(api.app, host="127.0.0.1", port=args.port, log_level="info")
"""#
}
