import Foundation

struct PipelineResult: Equatable {
    let status: PipelineStatus
    let webURL: URL?
    let updatedAt: Date?
    let startedAt: Date?
    let ref: String?

    init(status: PipelineStatus, webURL: URL?, updatedAt: Date?, startedAt: Date? = nil, ref: String? = nil) {
        self.status = status
        self.webURL = webURL
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.ref = ref
    }
}
