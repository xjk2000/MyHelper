import Foundation

struct RuntimeLoadContext {
    let now: Date
    let homeDirectory: URL
    let cacheDirectory: URL

    static func live(now: Date = Date()) -> RuntimeLoadContext {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["MYHELPER_HOME_OVERRIDE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let cache = environment["MYHELPER_CACHE_OVERRIDE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MyHelper", isDirectory: true)
            ?? home.appendingPathComponent("Library/Caches/MyHelper", isDirectory: true)
        return RuntimeLoadContext(now: now, homeDirectory: home, cacheDirectory: cache)
    }
}

protocol RuntimeUsageProvider {
    var scope: RuntimeScope { get }
    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot
    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard?
}

struct RuntimeProviderRegistry {
    let providers: [any RuntimeUsageProvider]

    init(providers: [any RuntimeUsageProvider]? = nil) {
        let baseProviders = providers ?? [
            CodexRuntimeProvider(),
            ClaudeCodeRuntimeProvider()
        ]
        let filters = ProcessInfo.processInfo.environment["MYHELPER_RUNTIME_FILTER"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            ?? []
        if filters.isEmpty {
            self.providers = baseProviders
        } else {
            self.providers = baseProviders.filter { provider in
                filters.contains(provider.scope.runtimeId) || filters.contains(provider.scope.rawValue.lowercased())
            }
        }
    }

    func provider(for scope: RuntimeScope) -> (any RuntimeUsageProvider)? {
        providers.first { $0.scope == scope }
    }
}

struct CodexRuntimeProvider: RuntimeUsageProvider {
    let scope: RuntimeScope = .codex

    func loadSnapshot(context: RuntimeLoadContext) -> RuntimeUsageSnapshot {
        let snapshot = CodexUsageReader().load()
        let status: RuntimeMenuStatus
        if snapshot.primary != nil || snapshot.secondary != nil {
            status = .available
        } else if snapshot.local != nil {
            status = .localOnly
        } else {
            status = .unavailable
        }

        return RuntimeUsageSnapshot(
            scope: scope,
            snapshot: snapshot,
            status: status,
            quotaSourceLabel: status == .localOnly ? "Relay/API key local records" : "Codex app-server + local records",
            usageSourceLabel: "Codex local state"
        )
    }

    func loadTaskBoard(context: RuntimeLoadContext) -> TaskBoard? {
        CodexUsageReader().loadTaskBoard()
    }
}
