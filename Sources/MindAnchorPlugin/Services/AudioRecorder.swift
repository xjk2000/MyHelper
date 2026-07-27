import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?

    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                AppLog.capture.info("microphone_permission_resolved platform=macOS granted=\(granted, privacy: .public)")
                continuation.resume(returning: granted)
            }
        }
    }

    func start(processId: UUID) throws -> URL {
        let audioURL = try Self.makeAudioURL(processId: processId)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        // macOS 没有 AVAudioSession；输入设备选择和权限由系统隐私设置与 AVAudioRecorder 共同处理。
        // 后续如果支持设备选择，再通过 AVCaptureDevice/AVAudioEngine 做更细的路由控制。
        let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
        recorder.delegate = self
        recorder.record()
        self.recorder = recorder

        AppLog.capture.info("recording_started platform=macOS processId=\(processId.uuidString, privacy: .public) audioFile=\(audioURL.lastPathComponent, privacy: .public)")
        return audioURL
    }

    func stop(processId: UUID) {
        recorder?.stop()
        recorder = nil
        AppLog.capture.info("recording_finished platform=macOS processId=\(processId.uuidString, privacy: .public)")
    }

    private static func makeAudioURL(processId: UUID) throws -> URL {
        let baseURL = URL(fileURLWithPath: AudioStorageDefaults.currentDirectoryPath, isDirectory: true)

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        AppLog.capture.info("recording_storage_resolved platform=macOS processId=\(processId.uuidString, privacy: .public) directory=\(baseURL.path, privacy: .public)")
        return baseURL.appendingPathComponent("\(processId.uuidString).wav")
    }
}
