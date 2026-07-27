import Foundation

final class MultiRuntimeUsageReader {
    private let registry: RuntimeProviderRegistry
    private let aggregator: AgentUsageAggregator

    init(
        registry: RuntimeProviderRegistry = RuntimeProviderRegistry(),
        aggregator: AgentUsageAggregator = AgentUsageAggregator()
    ) {
        self.registry = registry
        self.aggregator = aggregator
    }

    func load() -> MultiRuntimeUsageSnapshot {
        let context = RuntimeLoadContext.live()
        let runtimeSnapshots = registry.providers.map { provider in
            provider.loadSnapshot(context: context)
        }
        let refreshedAt = Date()
        let aggregate = aggregator.aggregate(runtimeSnapshots, at: refreshedAt)
        return MultiRuntimeUsageSnapshot(
            refreshedAt: refreshedAt,
            runtimes: runtimeSnapshots,
            aggregate: aggregate
        )
    }

    func loadTaskBoard(scope: RuntimeScope) -> TaskBoard? {
        let context = RuntimeLoadContext.live()
        return registry.provider(for: scope)?.loadTaskBoard(context: context)
    }
}
