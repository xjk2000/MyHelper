import Foundation

enum CloneProtocol: String, Codable, CaseIterable, Identifiable, Equatable {
    case https
    case ssh
    var id: String { rawValue }
    var displayName: String { self == .https ? "HTTPS + PAT" : "SSH" }
}
