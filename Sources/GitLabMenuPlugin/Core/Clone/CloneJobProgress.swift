import Foundation

typealias CloneProgressCallback = @Sendable (Int, CloneItemState) -> Void
typealias CloneLogCallback = @Sendable (GitOutput) -> Void
