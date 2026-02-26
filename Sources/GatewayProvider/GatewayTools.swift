import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-tools.ts
// Ported from packages/gateway/src/tool/parallel-search.ts
// Ported from packages/gateway/src/tool/perplexity-search.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public struct GatewayTools: Sendable {
    public init() {}

    @discardableResult
    public func parallelSearch(_ config: GatewayParallelSearchConfig = .init()) -> Tool {
        gatewayParallelSearchToolFactory(config)
    }

    @discardableResult
    public func perplexitySearch(_ config: GatewayPerplexitySearchConfig = .init()) -> Tool {
        gatewayPerplexitySearchToolFactory(config)
    }
}

public let gatewayTools = GatewayTools()

// MARK: - Parallel Search

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
}

private let parallelSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "required": .array([.string("objective")]),
    "properties": .object([
        "objective": .object([
            "type": .string("string"),
            "description": .string("Natural-language description of the web research goal, including source or freshness guidance and broader context from the task. Maximum 5000 characters.")
        ]),
        "search_queries": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string("Optional search queries to supplement the objective. Maximum 200 characters per query.")
        ]),
        "mode": .object([
            "type": .string("string"),
            "enum": .array([.string("one-shot"), .string("agentic")]),
            "description": .string("Mode preset: \"one-shot\" for comprehensive results with longer excerpts (default), \"agentic\" for concise, token-efficient results for multi-step workflows.")
        ]),
        "max_results": .object([
            "type": .string("number"),
            "description": .string("Maximum number of results to return (1-20). Defaults to 10 if not specified.")
        ]),
        "source_policy": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "include_domains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "exclude_domains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "after_date": .object([
                    "type": .string("string")
                ]),
            ]),
            "description": .string("Source policy for controlling which domains to include/exclude and freshness.")
        ]),
        "excerpts": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "max_chars_per_result": .object([
                    "type": .string("number")
                ]),
                "max_chars_total": .object([
                    "type": .string("number")
                ]),
            ]),
            "description": .string("Excerpt configuration for controlling result length.")
        ]),
        "fetch_policy": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "max_age_seconds": .object([
                    "type": .string("number")
                ])
            ]),
            "description": .string("Fetch policy for controlling content freshness.")
        ]),
    ])
])

private let parallelSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("searchId"), .string("results")]),
            "properties": .object([
                "searchId": .object(["type": .string("string")]),
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([.string("url"), .string("title"), .string("excerpt")]),
                        "properties": .object([
                            "url": .object(["type": .string("string")]),
                            "title": .object(["type": .string("string")]),
                            "excerpt": .object(["type": .string("string")]),
                            "publishDate": .object([
                                "anyOf": .array([
                                    .object(["type": .string("string")]),
                                    .object(["type": .string("null")]),
                                ])
                            ]),
                            "relevanceScore": .object(["type": .string("number")]),
                        ])
                    ])
                ])
            ])
        ]),
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("error"), .string("message")]),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("invalid_input"),
                        .string("configuration_error"),
                        .string("unknown"),
                    ])
                ]),
                "statusCode": .object(["type": .string("number")]),
                "message": .object(["type": .string("string")]),
            ])
        ]),
    ])
])

public let gatewayParallelSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "gateway.parallel_search",
    name: "parallel_search",
    inputSchema: FlexibleSchema(jsonSchema(parallelSearchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(parallelSearchOutputJSONSchema))
) { (config: GatewayParallelSearchConfig) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeGatewayParallelSearchConfig(config)
    return options
}

private func encodeGatewayParallelSearchConfig(_ config: GatewayParallelSearchConfig) -> [String: JSONValue] {
    var args: [String: JSONValue] = [:]

    if let mode = config.mode {
        args["mode"] = .string(mode.rawValue)
    }

    if let maxResults = config.maxResults {
        args["maxResults"] = .number(Double(maxResults))
    }

    if let source = config.sourcePolicy {
        var payload: [String: JSONValue] = [:]
        if let include = source.includeDomains {
            payload["includeDomains"] = .array(include.map(JSONValue.string))
        }
        if let exclude = source.excludeDomains {
            payload["excludeDomains"] = .array(exclude.map(JSONValue.string))
        }
        if let afterDate = source.afterDate {
            payload["afterDate"] = .string(afterDate)
        }
        if !payload.isEmpty {
            args["sourcePolicy"] = .object(payload)
        }
    }

    if let excerpts = config.excerpts {
        var payload: [String: JSONValue] = [:]
        if let maxCharsPerResult = excerpts.maxCharsPerResult {
            payload["maxCharsPerResult"] = .number(Double(maxCharsPerResult))
        }
        if let maxCharsTotal = excerpts.maxCharsTotal {
            payload["maxCharsTotal"] = .number(Double(maxCharsTotal))
        }
        if !payload.isEmpty {
            args["excerpts"] = .object(payload)
        }
    }

    if let fetchPolicy = config.fetchPolicy, let maxAgeSeconds = fetchPolicy.maxAgeSeconds {
        args["fetchPolicy"] = .object(["maxAgeSeconds": .number(Double(maxAgeSeconds))])
    }

    return args
}

// MARK: - Perplexity Search

public struct GatewayPerplexitySearchConfig: Sendable, Equatable {
    public enum Recency: String, Sendable, Equatable, Codable {
        case day
        case week
        case month
        case year
    }

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
}

private let perplexitySearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "required": .array([.string("query")]),
    "properties": .object([
        "query": .object([
            "anyOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "maxItems": .number(5),
                ]),
            ]),
            "description": .string("Search query (string) or multiple queries (array of up to 5 strings). Multi-query searches return combined results from all queries.")
        ]),
        "max_results": .object([
            "type": .string("number"),
            "description": .string("Maximum number of search results to return (1-20, default: 10)")
        ]),
        "max_tokens_per_page": .object([
            "type": .string("number"),
            "description": .string("Maximum number of tokens to extract per search result page (256-2048, default: 2048)")
        ]),
        "max_tokens": .object([
            "type": .string("number"),
            "description": .string("Maximum total tokens across all search results (default: 25000, max: 1000000)")
        ]),
        "country": .object([
            "type": .string("string"),
            "description": .string("Two-letter ISO 3166-1 alpha-2 country code for regional search results (e.g., 'US', 'GB', 'FR')")
        ]),
        "search_domain_filter": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ]),
        "search_language_filter": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ]),
        "search_after_date": .object(["type": .string("string")]),
        "search_before_date": .object(["type": .string("string")]),
        "last_updated_after_filter": .object(["type": .string("string")]),
        "last_updated_before_filter": .object(["type": .string("string")]),
        "search_recency_filter": .object([
            "type": .string("string"),
            "enum": .array([.string("day"), .string("week"), .string("month"), .string("year")])
        ]),
    ])
])

private let perplexitySearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("results"), .string("id")]),
            "properties": .object([
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([.string("title"), .string("url"), .string("snippet")]),
                        "properties": .object([
                            "title": .object(["type": .string("string")]),
                            "url": .object(["type": .string("string")]),
                            "snippet": .object(["type": .string("string")]),
                            "date": .object(["type": .string("string")]),
                            "lastUpdated": .object(["type": .string("string")]),
                        ])
                    ])
                ]),
                "id": .object(["type": .string("string")]),
            ])
        ]),
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("error"), .string("message")]),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("invalid_input"),
                        .string("unknown"),
                    ])
                ]),
                "statusCode": .object(["type": .string("number")]),
                "message": .object(["type": .string("string")]),
            ])
        ]),
    ])
])

public let gatewayPerplexitySearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "gateway.perplexity_search",
    name: "perplexity_search",
    inputSchema: FlexibleSchema(jsonSchema(perplexitySearchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(perplexitySearchOutputJSONSchema))
) { (config: GatewayPerplexitySearchConfig) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeGatewayPerplexitySearchConfig(config)
    return options
}

private func encodeGatewayPerplexitySearchConfig(_ config: GatewayPerplexitySearchConfig) -> [String: JSONValue] {
    var args: [String: JSONValue] = [:]

    if let maxResults = config.maxResults {
        args["maxResults"] = .number(Double(maxResults))
    }

    if let maxTokensPerPage = config.maxTokensPerPage {
        args["maxTokensPerPage"] = .number(Double(maxTokensPerPage))
    }

    if let maxTokens = config.maxTokens {
        args["maxTokens"] = .number(Double(maxTokens))
    }

    if let country = config.country {
        args["country"] = .string(country)
    }

    if let filter = config.searchDomainFilter {
        args["searchDomainFilter"] = .array(filter.map(JSONValue.string))
    }

    if let filter = config.searchLanguageFilter {
        args["searchLanguageFilter"] = .array(filter.map(JSONValue.string))
    }

    if let recency = config.searchRecencyFilter {
        args["searchRecencyFilter"] = .string(recency.rawValue)
    }

    return args
}
