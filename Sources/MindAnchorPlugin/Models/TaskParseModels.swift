import Foundation

struct TaskParseInput: Sendable {
    let text: String
    let capturedAt: Date
    let timeZoneIdentifier: String
    let localeIdentifier: String
}

struct ParsedTaskDraft: Sendable {
    let title: String
    let originalText: String
    let sourceChannel: SourceChannel
    let assignee: String?
    let deadline: Date?
    let confidence: Double
    let needsReview: Bool
}

struct TranscriptionContext: Sendable {
    let processId: UUID
    let platform: String
    let localeIdentifier: String
    let maxDurationSeconds: Int
}

struct TranscriptionResult: Sendable {
    let text: String
    let durationMilliseconds: Int?
    let provider: String
}
