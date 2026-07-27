import AppKit
import Foundation
import ImageIO
import Vision

struct ScreenCaptureOCRResult: Sendable {
    let text: String
    let screenshotURL: URL
}

@MainActor
struct ScreenCaptureOCRService {
    func captureAndRecognize(processId: UUID) async throws -> ScreenCaptureOCRResult {
        let screenshotURL = try makeScreenshotURL(processId: processId)
        try await runScreenCapture(to: screenshotURL, processId: processId)

        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            AppLog.capture.info("screenshot_capture_cancelled processId=\(processId.uuidString, privacy: .public) reason=file_missing")
            throw ScreenCaptureOCRError.cancelled
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: screenshotURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize > 0 else {
            AppLog.capture.info("screenshot_capture_cancelled processId=\(processId.uuidString, privacy: .public) reason=empty_file")
            throw ScreenCaptureOCRError.cancelled
        }

        let text = try recognizeText(in: screenshotURL, processId: processId)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenCaptureOCRError.noTextRecognized
        }

        AppLog.capture.info("screenshot_ocr_completed processId=\(processId.uuidString, privacy: .public) textLength=\(text.count, privacy: .public) screenshotFile=\(screenshotURL.lastPathComponent, privacy: .public)")
        return ScreenCaptureOCRResult(text: text, screenshotURL: screenshotURL)
    }

    private func runScreenCapture(to url: URL, processId: UUID) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]

        AppLog.capture.info("screenshot_capture_started processId=\(processId.uuidString, privacy: .public)")

        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ScreenCaptureOCRError.captureFailed(code: finishedProcess.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func recognizeText(in url: URL, processId: UUID) throws -> String {
        guard
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw ScreenCaptureOCRError.imageLoadFailed
        }

        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                AppLog.capture.error("screenshot_ocr_request_failed processId=\(processId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
                return
            }

            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            recognizedLines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return recognizedLines.joined(separator: "\n")
    }

    private func makeScreenshotURL(processId: UUID) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("MyHelper/MindAnchor/Screenshots", isDirectory: true)

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("\(processId.uuidString).png")
    }
}

enum ScreenCaptureOCRError: LocalizedError {
    case cancelled
    case captureFailed(code: Int32)
    case imageLoadFailed
    case noTextRecognized

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消截图"
        case let .captureFailed(code):
            return "截图失败：退出码 \(code)"
        case .imageLoadFailed:
            return "无法读取截图"
        case .noTextRecognized:
            return "截图中没有识别到文字"
        }
    }
}
