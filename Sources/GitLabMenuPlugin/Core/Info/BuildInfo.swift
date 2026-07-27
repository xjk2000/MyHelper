import Foundation

enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    static var commit: String {
        // 通过 Info.plist 注入 GIT_COMMIT_HASH(在 Task 18 落实 build phase);
        // 现阶段缺失则显示 "dev"
        Bundle.main.infoDictionary?["GIT_COMMIT_HASH"] as? String ?? "dev"
    }
}
