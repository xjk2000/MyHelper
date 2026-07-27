import AppKit
import UniformTypeIdentifiers
import Vision

enum QRCodeImportService {
    enum ImportError: LocalizedError {
        case noImageOnPasteboard
        case unreadableImage
        case noQRCode

        var errorDescription: String? {
            switch self {
            case .noImageOnPasteboard:
                return "剪贴板里没有可识别的图片"
            case .unreadableImage:
                return "无法读取这张图片"
            case .noQRCode:
                return "没有在图片中识别到二维码"
            }
        }
    }

    static func scanImageFile() throws -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择二维码图片"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        guard let image = NSImage(contentsOf: url) else {
            throw ImportError.unreadableImage
        }

        return try scan(image: image)
    }

    static func scanScreenSelection() throws -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwoFATool-screen-qr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else {
            throw ImportError.unreadableImage
        }

        return try scan(image: image)
    }

    static func scanPasteboardImage() throws -> String {
        guard
            let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
            let image = images.first
        else {
            throw ImportError.noImageOnPasteboard
        }

        return try scan(image: image)
    }

    static func scan(image: NSImage) throws -> String {
        guard let cgImage = image.cgImageForQRCodeScanning() else {
            throw ImportError.unreadableImage
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard
            let observations = request.results,
            let payload = observations.compactMap(\.payloadStringValue).first
        else {
            throw ImportError.noQRCode
        }

        return payload
    }
}

private extension NSImage {
    func cgImageForQRCodeScanning() -> CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
