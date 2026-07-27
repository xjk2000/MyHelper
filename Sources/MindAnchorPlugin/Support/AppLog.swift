import Foundation
import OSLog

enum AppLog {
    static let subsystem = "com.mindanchor.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let capture = Logger(subsystem: subsystem, category: "TaskCapture")
    static let stt = Logger(subsystem: subsystem, category: "STT")
    static let aiParse = Logger(subsystem: subsystem, category: "AIParse")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let notification = Logger(subsystem: subsystem, category: "Notification")
    static let security = Logger(subsystem: subsystem, category: "Security")
}
