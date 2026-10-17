import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GatewayTools: Sendable {
    public init() {}

    public func parallelSearch(_ config: GatewayParallelSearchConfig = .init()) -> Tool {
        gatewayParallelSearchToolFactory(config)
    }

    public func perplexitySearch(_ config: GatewayPerplexitySearchConfig = .init()) -> Tool {
        gatewayPerplexitySearchToolFactory(config)
    }

    public func browserbaseFetch(_ config: GatewayBrowserbaseFetchConfig = .init()) -> Tool {
        gatewayBrowserbaseFetchToolFactory(config)
    }

    public func browserbaseSearch(_ config: GatewayBrowserbaseSearchConfig = .init()) -> Tool {
        gatewayBrowserbaseSearchToolFactory(config)
    }

    public func exaSearch(_ config: GatewayExaSearchConfig = .init()) -> Tool {
        gatewayExaSearchToolFactory(config)
    }

    public func takoSearch(_ config: GatewayTakoSearchConfig = .init()) -> Tool {
        gatewayTakoSearchToolFactory(config)
    }
}

public let gatewayTools = GatewayTools()

public struct GatewayParallelSearchConfig: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable, Codable {
        case oneShot = "one-shot"
        case agentic
    }

    public struct SourcePolicy: Sendable, Equatable {
        public let includeDomains: [String]?
        public let excludeDomains: [String]?
        public let afterDate: String?

        public init(includeDomains: [String]? = nil, excludeDomains: [String]? = nil, afterDate: String? = nil) {
            self.includeDomains = includeDomains
            self.excludeDomains = excludeDomains
            self.afterDate = afterDate
        }
    }

    public struct Excerpts: Sendable, Equatable {
        public let maxCharsPerResult: Int?
        public let maxCharsTotal: Int?

        public init(maxCharsPerResult: Int? = nil, maxCharsTotal: Int? = nil) {
            self.maxCharsPerResult = maxCharsPerResult
            self.maxCharsTotal = maxCharsTotal
        }
    }

    public struct FetchPolicy: Sendable, Equatable {
        public let maxAgeSeconds: Int?

        public init(maxAgeSeconds: Int? = nil) {
            self.maxAgeSeconds = maxAgeSeconds
        }
    }

    public let mode: Mode?
    public let maxResults: Int?
    public let sourcePolicy: SourcePolicy?
    public let excerpts: Excerpts?
    public let fetchPolicy: FetchPolicy?

    public init(
        mode: Mode? = nil,
        maxResults: Int? = nil,
        sourcePolicy: SourcePolicy? = nil,
        excerpts: Excerpts? = nil,
        fetchPolicy: FetchPolicy? = nil
    ) {
        self.mode = mode
        self.maxResults = maxResults
        self.sourcePolicy = sourcePolicy
        self.excerpts = excerpts
        self.fetchPolicy = fetchPolicy
    }

    var args: [String: JSONValue] {
        [
            "mode": mode.map { .string($0.rawValue) },
            "maxResults": maxResults.map { .number(Double($0)) },
            "sourcePolicy": sourcePolicy.map { source in
                .object([
                    "includeDomains": source.includeDomains.map { .array($0.map(JSONValue.string)) },
                    "excludeDomains": source.excludeDomains.map { .array($0.map(JSONValue.string)) },
                    "afterDate": source.afterDate.map(JSONValue.string),
                ].compactMapValues { $0 })
            },
            "excerpts": excerpts.map { excerpts in
                .object([
                    "maxCharsPerResult": excerpts.maxCharsPerResult.map { .number(Double($0)) },
                    "maxCharsTotal": excerpts.maxCharsTotal.map { .number(Double($0)) },
                ].compactMapValues { $0 })
            },
            "fetchPolicy": fetchPolicy.map { policy in
                .object(["maxAgeSeconds": policy.maxAgeSeconds.map { .number(Double($0)) }].compactMapValues { $0 })
            },
        ].compactMapValues { $0 }
    }
}

public struct GatewayPerplexitySearchConfig: Sendable, Equatable {
    public enum Recency: String, Sendable, Equatable, Codable { case day, week, month, year }

    public let maxResults: Int?
    public let maxTokensPerPage: Int?
    public let maxTokens: Int?
    public let country: String?
    public let searchDomainFilter: [String]?
    public let searchLanguageFilter: [String]?
    public let searchRecencyFilter: Recency?

    public init(
        maxResults: Int? = nil,
        maxTokensPerPage: Int? = nil,
        maxTokens: Int? = nil,
        country: String? = nil,
        searchDomainFilter: [String]? = nil,
        searchLanguageFilter: [String]? = nil,
        searchRecencyFilter: Recency? = nil
    ) {
        self.maxResults = maxResults
        self.maxTokensPerPage = maxTokensPerPage
        self.maxTokens = maxTokens
        self.country = country
        self.searchDomainFilter = searchDomainFilter
        self.searchLanguageFilter = searchLanguageFilter
        self.searchRecencyFilter = searchRecencyFilter
    }

    var args: [String: JSONValue] {
        [
            "maxResults": maxResults.map { .number(Double($0)) },
            "maxTokensPerPage": maxTokensPerPage.map { .number(Double($0)) },
            "maxTokens": maxTokens.map { .number(Double($0)) },
            "country": country.map(JSONValue.string),
            "searchDomainFilter": searchDomainFilter.map { .array($0.map(JSONValue.string)) },
            "searchLanguageFilter": searchLanguageFilter.map { .array($0.map(JSONValue.string)) },
            "searchRecencyFilter": searchRecencyFilter.map { .string($0.rawValue) },
        ].compactMapValues { $0 }
    }
}

public let gatewayParallelSearchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.parallel_search",
    name: "parallel_search",
    inputSchema: gatewayToolSchema(parallelSearchInputJSONSchema),
    outputSchema: gatewayToolSchema(parallelSearchOutputJSONSchema)
) { (config: GatewayParallelSearchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}

public let gatewayPerplexitySearchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.perplexity_search",
    name: "perplexity_search",
    inputSchema: gatewayToolSchema(perplexitySearchInputJSONSchema),
    outputSchema: gatewayToolSchema(perplexitySearchOutputJSONSchema)
) { (config: GatewayPerplexitySearchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}

public let gatewayBrowserbaseFetchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.browserbase_fetch",
    name: "browserbase_fetch",
    inputSchema: gatewayToolSchema(browserbaseFetchInputJSONSchema),
    outputSchema: gatewayToolSchema(browserbaseFetchOutputJSONSchema)
) { (config: GatewayBrowserbaseFetchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}

public let gatewayBrowserbaseSearchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.browserbase_search",
    name: "browserbase_search",
    inputSchema: gatewayToolSchema(browserbaseSearchInputJSONSchema),
    outputSchema: gatewayToolSchema(browserbaseSearchOutputJSONSchema)
) { (config: GatewayBrowserbaseSearchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}

public let gatewayExaSearchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.exa_search",
    name: "exa_search",
    inputSchema: gatewayToolSchema(exaSearchInputJSONSchema),
    outputSchema: gatewayToolSchema(exaSearchOutputJSONSchema)
) { (config: GatewayExaSearchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}

public let gatewayTakoSearchToolFactory = createProviderExecutedToolFactory(
    id: "gateway.tako_search",
    name: "tako_search",
    inputSchema: gatewayToolSchema(takoSearchInputJSONSchema),
    outputSchema: gatewayToolSchema(takoSearchOutputJSONSchema)
) { (config: GatewayTakoSearchConfig) in
    ProviderExecutedToolFactoryOptions(args: config.args)
}
