import AISDKProvider

// Generated from packages/gateway/src/tool at 8a5233b15b1e69573d63faee6cd0014559252ee4.

let parallelSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "objective": .object([
            "type": .string("string"),
            "description": .string("Natural-language description of the web research goal, including source or freshness guidance and broader context from the task. Maximum 5000 characters."),
        ]),
        "search_queries": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
            ]),
            "description": .string("Optional search queries to supplement the objective. Maximum 200 characters per query."),
        ]),
        "mode": .object([
            "type": .string("string"),
            "enum": .array([
                .string("one-shot"),
                .string("agentic"),
            ]),
            "description": .string("Mode preset: \"one-shot\" for comprehensive results with longer excerpts (default), \"agentic\" for concise, token-efficient results for multi-step workflows."),
        ]),
        "max_results": .object([
            "type": .string("number"),
            "description": .string("Maximum number of results to return (1-20). Defaults to 10 if not specified."),
        ]),
        "source_policy": .object([
            "type": .string("object"),
            "properties": .object([
                "include_domains": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                    ]),
                    "description": .string("Limit results to these domains. Use plain domain names only — e.g. example.com or sub.example.gov, or a bare extension like .edu. Do not include a scheme, path, or port (e.g. not https://example.com/page)."),
                ]),
                "exclude_domains": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                    ]),
                    "description": .string("Exclude results from these domains. Use plain domain names only — e.g. example.com or sub.example.gov, or a bare extension like .edu. Do not include a scheme, path, or port (e.g. not https://example.com/page)."),
                ]),
                "after_date": .object([
                    "type": .string("string"),
                    "description": .string("Only include results published after this date. Use an ISO 8601 calendar date formatted YYYY-MM-DD (e.g. 2025-01-01); do not include a time."),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Source policy for controlling which domains to include/exclude and freshness."),
        ]),
        "excerpts": .object([
            "type": .string("object"),
            "properties": .object([
                "max_chars_per_result": .object([
                    "type": .string("number"),
                    "description": .string("Maximum characters per result."),
                ]),
                "max_chars_total": .object([
                    "type": .string("number"),
                    "description": .string("Maximum total characters across all results."),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Excerpt configuration for controlling result length."),
        ]),
        "fetch_policy": .object([
            "type": .string("object"),
            "properties": .object([
                "max_age_seconds": .object([
                    "type": .string("number"),
                    "description": .string("Maximum age in seconds for cached content. Set to 0 to always fetch fresh content."),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Fetch policy for controlling content freshness."),
        ]),
    ]),
    "required": .array([
        .string("objective"),
    ]),
    "additionalProperties": .bool(false),
])

let parallelSearchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "searchId": .object([
                    "type": .string("string"),
                ]),
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "url": .object([
                                "type": .string("string"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                            ]),
                            "excerpt": .object([
                                "type": .string("string"),
                            ]),
                            "publishDate": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "relevanceScore": .object([
                                "type": .string("number"),
                            ]),
                        ]),
                        "required": .array([
                            .string("url"),
                            .string("title"),
                            .string("excerpt"),
                        ]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([
                .string("searchId"),
                .string("results"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        .object([
            "type": .string("object"),
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
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

let perplexitySearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "query": .object([
            "anyOf": .array([
                .object([
                    "type": .string("string"),
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                    ]),
                ]),
            ]),
            "description": .string("Search query (string) or multiple queries (array of up to 5 strings). Multi-query searches return combined results from all queries."),
        ]),
        "max_results": .object([
            "type": .string("number"),
            "description": .string("Maximum number of search results to return (1-20, default: 10)"),
        ]),
        "max_tokens_per_page": .object([
            "type": .string("number"),
            "description": .string("Maximum number of tokens to extract per search result page (256-2048, default: 2048)"),
        ]),
        "max_tokens": .object([
            "type": .string("number"),
            "description": .string("Maximum total tokens across all search results (default: 25000, max: 1000000)"),
        ]),
        "country": .object([
            "type": .string("string"),
            "description": .string("Two-letter ISO 3166-1 alpha-2 country code for regional search results (e.g., 'US', 'GB', 'FR')"),
        ]),
        "search_domain_filter": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
            ]),
            "description": .string("List of domains to include or exclude from search results (max 20). To include: ['nature.com', 'science.org']. To exclude: ['-example.com', '-spam.net']"),
        ]),
        "search_language_filter": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
            ]),
            "description": .string("List of ISO 639-1 language codes to filter results (max 10, lowercase). Examples: ['en', 'fr', 'de']"),
        ]),
        "search_after_date": .object([
            "type": .string("string"),
            "description": .string("Include only results published after this date. Format: 'MM/DD/YYYY' (e.g., '3/1/2025'). Cannot be used with search_recency_filter."),
        ]),
        "search_before_date": .object([
            "type": .string("string"),
            "description": .string("Include only results published before this date. Format: 'MM/DD/YYYY' (e.g., '3/15/2025'). Cannot be used with search_recency_filter."),
        ]),
        "last_updated_after_filter": .object([
            "type": .string("string"),
            "description": .string("Include only results last updated after this date. Format: 'MM/DD/YYYY' (e.g., '3/1/2025'). Cannot be used with search_recency_filter."),
        ]),
        "last_updated_before_filter": .object([
            "type": .string("string"),
            "description": .string("Include only results last updated before this date. Format: 'MM/DD/YYYY' (e.g., '3/15/2025'). Cannot be used with search_recency_filter."),
        ]),
        "search_recency_filter": .object([
            "type": .string("string"),
            "enum": .array([
                .string("day"),
                .string("week"),
                .string("month"),
                .string("year"),
            ]),
            "description": .string("Filter results by relative time period. Cannot be used with search_after_date or search_before_date."),
        ]),
    ]),
    "required": .array([
        .string("query"),
    ]),
    "additionalProperties": .bool(false),
])

let perplexitySearchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string"),
                            ]),
                            "url": .object([
                                "type": .string("string"),
                            ]),
                            "snippet": .object([
                                "type": .string("string"),
                            ]),
                            "date": .object([
                                "type": .string("string"),
                            ]),
                            "lastUpdated": .object([
                                "type": .string("string"),
                            ]),
                        ]),
                        "required": .array([
                            .string("title"),
                            .string("url"),
                            .string("snippet"),
                        ]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
                "id": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("results"),
                .string("id"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        .object([
            "type": .string("object"),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("invalid_input"),
                        .string("unknown"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

let browserbaseFetchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "url": .object([
            "type": .string("string"),
            "format": .string("uri"),
            "description": .string("URL of the page to fetch."),
        ]),
        "allow_redirects": .object([
            "type": .string("boolean"),
            "description": .string("Whether to follow HTTP redirects (default: false)."),
        ]),
        "allow_insecure_ssl": .object([
            "type": .string("boolean"),
            "description": .string("Whether to bypass TLS certificate verification (default: false). Only use for trusted hosts."),
        ]),
        "proxies": .object([
            "type": .string("boolean"),
            "description": .string("Whether to route the request through Browserbase proxies (default: false)."),
        ]),
        "format": .object([
            "type": .string("string"),
            "enum": .array([
                .string("raw"),
                .string("json"),
                .string("markdown"),
            ]),
            "description": .string("Output format. raw returns the response body unchanged, markdown returns page content as Markdown, and json returns structured content using schema."),
        ]),
        "schema": .object([
            "type": .string("object"),
            "additionalProperties": .object([:]),
            "description": .string("JSON Schema for structured extraction. Only use with format set to json."),
        ]),
    ]),
    "required": .array([
        .string("url"),
    ]),
    "additionalProperties": .bool(false),
])

let browserbaseFetchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                ]),
                "content": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("string"),
                        ]),
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .object([:]),
                        ]),
                    ]),
                ]),
                "contentType": .object([
                    "type": .string("string"),
                ]),
                "encoding": .object([
                    "type": .string("string"),
                ]),
                "headers": .object([
                    "type": .string("object"),
                    "additionalProperties": .object([
                        "type": .string("string"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
            ]),
            "required": .array([
                .string("id"),
                .string("content"),
                .string("contentType"),
                .string("encoding"),
                .string("headers"),
                .string("statusCode"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        .object([
            "type": .string("object"),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("configuration_error"),
                        .string("execution_error"),
                        .string("invalid_input"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("unknown"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

let browserbaseSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "query": .object([
            "type": .string("string"),
            "minLength": .number(1),
            "maxLength": .number(200),
            "description": .string("Web search query. Must be between 1 and 200 characters."),
        ]),
        "num_results": .object([
            "type": .string("integer"),
            "minimum": .number(1),
            "maximum": .number(25),
            "description": .string("Maximum number of results to return (1-25, default: 10)."),
        ]),
    ]),
    "required": .array([
        .string("query"),
    ]),
    "additionalProperties": .bool(false),
])

let browserbaseSearchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                ]),
                "requestId": .object([
                    "type": .string("string"),
                ]),
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                            ]),
                            "url": .object([
                                "type": .string("string"),
                            ]),
                            "author": .object([
                                "type": .string("string"),
                            ]),
                            "favicon": .object([
                                "type": .string("string"),
                            ]),
                            "image": .object([
                                "type": .string("string"),
                            ]),
                            "publishedDate": .object([
                                "type": .string("string"),
                            ]),
                        ]),
                        "required": .array([
                            .string("id"),
                            .string("title"),
                            .string("url"),
                        ]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([
                .string("query"),
                .string("requestId"),
                .string("results"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        .object([
            "type": .string("object"),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("configuration_error"),
                        .string("execution_error"),
                        .string("invalid_input"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("unknown"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

let exaSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "query": .object([
            "type": .string("string"),
            "description": .string("Natural-language web search query. This is required."),
        ]),
        "type": .object([
            "type": .string("string"),
            "enum": .array([
                .string("auto"),
                .string("fast"),
                .string("instant"),
            ]),
            "description": .string("Search method. Use auto for the default balance of speed and quality."),
        ]),
        "num_results": .object([
            "type": .string("number"),
            "description": .string("Maximum number of results to return (1-100, default: 10)."),
        ]),
        "category": .object([
            "type": .string("string"),
            "enum": .array([
                .string("company"),
                .string("people"),
                .string("research paper"),
                .string("news"),
                .string("personal site"),
                .string("financial report"),
            ]),
            "description": .string("Optional content category to focus results."),
        ]),
        "user_location": .object([
            "type": .string("string"),
            "description": .string("Two-letter ISO country code such as 'US'."),
        ]),
        "include_domains": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
            ]),
            "description": .string("Only return results from these domains."),
        ]),
        "exclude_domains": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
            ]),
            "description": .string("Exclude results from these domains."),
        ]),
        "start_published_date": .object([
            "type": .string("string"),
            "description": .string("Only return links published after this ISO 8601 date."),
        ]),
        "end_published_date": .object([
            "type": .string("string"),
            "description": .string("Only return links published before this ISO 8601 date."),
        ]),
        "contents": .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("boolean"),
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "max_characters": .object([
                                    "type": .string("number"),
                                ]),
                                "include_html_tags": .object([
                                    "type": .string("boolean"),
                                ]),
                                "verbosity": .object([
                                    "type": .string("string"),
                                    "enum": .array([
                                        .string("compact"),
                                        .string("standard"),
                                        .string("full"),
                                    ]),
                                ]),
                                "include_sections": .object([
                                    "type": .string("array"),
                                    "items": .object([
                                        "type": .string("string"),
                                        "enum": .array([
                                            .string("header"),
                                            .string("navigation"),
                                            .string("banner"),
                                            .string("body"),
                                            .string("sidebar"),
                                            .string("footer"),
                                            .string("metadata"),
                                        ]),
                                    ]),
                                ]),
                                "exclude_sections": .object([
                                    "type": .string("array"),
                                    "items": .object([
                                        "type": .string("string"),
                                        "enum": .array([
                                            .string("header"),
                                            .string("navigation"),
                                            .string("banner"),
                                            .string("body"),
                                            .string("sidebar"),
                                            .string("footer"),
                                            .string("metadata"),
                                        ]),
                                    ]),
                                ]),
                            ]),
                            "required": .array([]),
                            "additionalProperties": .bool(false),
                        ]),
                    ]),
                ]),
                "highlights": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("boolean"),
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "query": .object([
                                    "type": .string("string"),
                                ]),
                                "max_characters": .object([
                                    "type": .string("number"),
                                ]),
                            ]),
                            "required": .array([]),
                            "additionalProperties": .bool(false),
                        ]),
                    ]),
                ]),
                "max_age_hours": .object([
                    "type": .string("number"),
                ]),
                "livecrawl_timeout": .object([
                    "type": .string("number"),
                ]),
                "subpages": .object([
                    "type": .string("number"),
                ]),
                "subpage_target": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("string"),
                        ]),
                        .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("string"),
                            ]),
                        ]),
                    ]),
                ]),
                "extras": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "links": .object([
                            "type": .string("number"),
                        ]),
                        "image_links": .object([
                            "type": .string("number"),
                        ]),
                    ]),
                    "required": .array([]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Controls extracted page content and freshness."),
        ]),
    ]),
    "required": .array([
        .string("query"),
    ]),
    "additionalProperties": .bool(false),
])

let exaSearchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "requestId": .object([
                    "type": .string("string"),
                ]),
                "searchType": .object([
                    "type": .string("string"),
                ]),
                "resolvedSearchType": .object([
                    "type": .string("string"),
                ]),
                "results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string"),
                            ]),
                            "url": .object([
                                "type": .string("string"),
                            ]),
                            "id": .object([
                                "type": .string("string"),
                            ]),
                            "publishedDate": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "author": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "image": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "favicon": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "text": .object([
                                "type": .string("string"),
                            ]),
                            "highlights": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("string"),
                                ]),
                            ]),
                            "highlightScores": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("number"),
                                ]),
                            ]),
                            "summary": .object([
                                "type": .string("string"),
                            ]),
                            "subpages": .object([
                                "type": .string("array"),
                                "items": .object([:]),
                            ]),
                            "extras": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "links": .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("string"),
                                        ]),
                                    ]),
                                    "imageLinks": .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("string"),
                                        ]),
                                    ]),
                                ]),
                                "required": .array([]),
                                "additionalProperties": .bool(false),
                            ]),
                        ]),
                        "required": .array([
                            .string("title"),
                            .string("url"),
                            .string("id"),
                        ]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
                "costDollars": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "total": .object([
                            "type": .string("number"),
                        ]),
                        "search": .object([
                            "type": .string("object"),
                            "additionalProperties": .object([
                                "type": .string("number"),
                            ]),
                        ]),
                    ]),
                    "required": .array([]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
            "required": .array([
                .string("requestId"),
                .string("results"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        .object([
            "type": .string("object"),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("invalid_input"),
                        .string("configuration_error"),
                        .string("execution_error"),
                        .string("unknown"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

let takoSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "query": .object([
            "type": .string("string"),
            "description": .string("Natural-language search query. Include the entity, metric, and time period. Quote a phrase to force it to one entity, for example \"Tesla\":PRODUCT price."),
        ]),
        "effort": .object([
            "type": .string("string"),
            "enum": .array([
                .string("deep"),
                .string("fast"),
                .string("instant"),
            ]),
            "description": .string("Search effort. fast is the balanced default, instant favors cached results and low latency, and deep broadens retrieval with reranking at higher cost and latency."),
        ]),
        "sources": .object([
            "type": .string("object"),
            "properties": .object([
                "data": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "count": .object([
                            "type": .string("number"),
                            "description": .string("Maximum number of data results to return (1-20). When include_contents is true, each additional result adds its own data surcharge."),
                        ]),
                        "include_contents": .object([
                            "type": .string("boolean"),
                            "description": .string("Inline rows for each data result. This adds a data surcharge based on row count and dataset source. To estimate cost, search with include_contents disabled and inspect cards.content.export_pricing. This applies to every returned card; limit sources.data.count and sources.data.max_rows to control cost."),
                        ]),
                        "mode": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("inline"),
                                .string("url"),
                            ]),
                            "description": .string("Requested data delivery mode. Search card data is always inline."),
                        ]),
                        "content_format": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("card_json"),
                                .string("csv"),
                                .string("json_compact"),
                                .string("json_records"),
                            ]),
                            "description": .string("Serialization for inlined card data."),
                        ]),
                        "max_rows": .object([
                            "type": .string("number"),
                            "description": .string("Maximum rows to inline per result. Omit to use the allowance in cards.content.export_pricing. A data surcharge applies per 1,000 exported rows; lower values reduce cost."),
                        ]),
                        "node_ids": .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("string"),
                            ]),
                            "description": .string("Data Graph node IDs to prioritize. Maximum 20."),
                        ]),
                        "strict": .object([
                            "type": .string("boolean"),
                            "description": .string("Only return cards matching node_ids. Requires a non-empty node_ids."),
                        ]),
                    ]),
                    "required": .array([]),
                    "additionalProperties": .bool(false),
                ]),
                "web": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "count": .object([
                            "type": .string("number"),
                            "description": .string("Maximum number of web results to return (1-20)."),
                        ]),
                        "include_contents": .object([
                            "type": .string("boolean"),
                            "description": .string("Inline extracted web page text. This can add a data charge."),
                        ]),
                        "category": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("finance"),
                                .string("news"),
                                .string("sports"),
                            ]),
                            "description": .string("Optional web-result category filter."),
                        ]),
                        "include_domains": .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("string"),
                            ]),
                            "description": .string("Only return results from these bare domains."),
                        ]),
                        "exclude_domains": .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("string"),
                            ]),
                            "description": .string("Exclude results from these bare domains."),
                        ]),
                        "snippet_max_chars": .object([
                            "type": .string("number"),
                            "description": .string("Maximum characters in each web-result snippet."),
                        ]),
                        "highlights": .object([
                            "type": .string("boolean"),
                            "description": .string("Include highlighted passages in web results. Defaults to true in AI Gateway."),
                        ]),
                        "article_content_max_chars": .object([
                            "type": .string("number"),
                            "description": .string("Maximum extracted characters per web page when including contents."),
                        ]),
                        "published_after": .object([
                            "type": .string("string"),
                            "description": .string("Keep results published on or after this ISO date (YYYY-MM-DD)."),
                        ]),
                        "published_before": .object([
                            "type": .string("string"),
                            "description": .string("Keep results published on or before this ISO date (YYYY-MM-DD)."),
                        ]),
                    ]),
                    "required": .array([]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Sources to search. Omit to search both curated data and the web. When provided, only keys present are searched."),
        ]),
        "location": .object([
            "type": .string("object"),
            "properties": .object([
                "latitude": .object([
                    "type": .string("number"),
                    "description": .string("Latitude between -90 and 90."),
                ]),
                "longitude": .object([
                    "type": .string("number"),
                    "description": .string("Longitude between -180 and 180."),
                ]),
            ]),
            "required": .array([
                .string("latitude"),
                .string("longitude"),
            ]),
            "additionalProperties": .bool(false),
            "description": .string("End-user coordinates for localized results."),
        ]),
        "country_code": .object([
            "type": .string("string"),
            "description": .string("Two-letter ISO 3166-1 country code, such as 'US'."),
        ]),
        "locale": .object([
            "type": .string("string"),
            "description": .string("BCP-47 locale, such as 'en-US'."),
        ]),
        "timezone": .object([
            "type": .string("string"),
            "description": .string("IANA timezone, such as 'America/New_York'."),
        ]),
        "output_settings": .object([
            "type": .string("object"),
            "properties": .object([
                "image_dark_mode": .object([
                    "type": .string("boolean"),
                    "description": .string("Render card preview images in dark mode."),
                ]),
                "force_refresh": .object([
                    "type": .string("boolean"),
                    "description": .string("Instant-effort only. Request a refreshed instant result."),
                ]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
            "description": .string("Controls card rendering in the search response."),
        ]),
        "include_related": .object([
            "type": .string("number"),
            "description": .string("Maximum related search suggestions to include (1-20)."),
        ]),
    ]),
    "required": .array([
        .string("query"),
    ]),
    "additionalProperties": .bool(false),
])

let takoSearchOutputJSONSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"),
            "properties": .object([
                "request_id": .object([
                    "type": .string("string"),
                ]),
                "cards": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "card_id": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "title": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "description": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "semantic_description": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "webpage_url": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "image_url": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "embed_url": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "sources": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "source_name": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                                "source_description": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                                "source_index": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([
                                                        .string("data"),
                                                        .string("web"),
                                                    ]),
                                                ]),
                                                "source_text": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                                "url": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("source_index"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "methodologies": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "methodology_name": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                                "methodology_description": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("methodology_name"),
                                                .string("methodology_description"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "source_indexes": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("string"),
                                            "enum": .array([
                                                .string("data"),
                                                .string("web"),
                                            ]),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "card_type": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "relevance": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                        "enum": .array([
                                            .string("High"),
                                            .string("Low"),
                                            .string("Medium"),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "content": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("object"),
                                        "properties": .object([
                                            "content_format": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                        "enum": .array([
                                                            .string("card_json"),
                                                            .string("csv"),
                                                            .string("json_compact"),
                                                            .string("json_records"),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "cost": .object([
                                                "type": .string("number"),
                                            ]),
                                            "data": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "records": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("array"),
                                                        "items": .object([
                                                            "type": .string("object"),
                                                            "additionalProperties": .object([
                                                                "anyOf": .array([
                                                                    .object([
                                                                        "anyOf": .array([
                                                                            .object([
                                                                                "type": .string("boolean"),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("number"),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("string"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    .object([
                                                                        "type": .string("null"),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "dataset": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([
                                                            "columns": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("object"),
                                                                    "properties": .object([
                                                                        "name": .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        "type": .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("boolean"),
                                                                                .string("date"),
                                                                                .string("datetime"),
                                                                                .string("number"),
                                                                                .string("string"),
                                                                            ]),
                                                                        ]),
                                                                        "unit": .object([
                                                                            "anyOf": .array([
                                                                                .object([
                                                                                    "type": .string("string"),
                                                                                ]),
                                                                                .object([
                                                                                    "type": .string("null"),
                                                                                ]),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    "required": .array([
                                                                        .string("name"),
                                                                        .string("type"),
                                                                    ]),
                                                                    "additionalProperties": .bool(false),
                                                                ]),
                                                            ]),
                                                            "rows": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("array"),
                                                                    "items": .object([
                                                                        "anyOf": .array([
                                                                            .object([
                                                                                "anyOf": .array([
                                                                                    .object([
                                                                                        "type": .string("boolean"),
                                                                                    ]),
                                                                                    .object([
                                                                                        "type": .string("number"),
                                                                                    ]),
                                                                                    .object([
                                                                                        "type": .string("string"),
                                                                                    ]),
                                                                                ]),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("null"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                            "total_rows": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "truncated": .object([
                                                                "type": .string("boolean"),
                                                            ]),
                                                            "ref": .object([
                                                                "type": .string("string"),
                                                            ]),
                                                            "sources": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("object"),
                                                                    "properties": .object([
                                                                        "name": .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        "index": .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("data"),
                                                                                .string("web"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    "required": .array([
                                                                        .string("name"),
                                                                    ]),
                                                                    "additionalProperties": .bool(false),
                                                                ]),
                                                            ]),
                                                            "provenance": .object([
                                                                "type": .string("string"),
                                                                "enum": .array([
                                                                    .string("query"),
                                                                    .string("web_extraction"),
                                                                ]),
                                                            ]),
                                                        ]),
                                                        "required": .array([
                                                            .string("columns"),
                                                            .string("rows"),
                                                            .string("total_rows"),
                                                            .string("truncated"),
                                                            .string("ref"),
                                                            .string("sources"),
                                                        ]),
                                                        "additionalProperties": .bool(false),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "card_data": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([:]),
                                                        "required": .array([]),
                                                        "additionalProperties": .object([:]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "card_data_schema": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([:]),
                                                        "required": .array([]),
                                                        "additionalProperties": .object([:]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "url": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "expires_at": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "total_rows": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("number"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "truncated": .object([
                                                "type": .string("boolean"),
                                            ]),
                                            "export_pricing": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([
                                                            "baseline_usd": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "free_rows": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "max_rows_ceiling": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "row_cpm_usd": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                        ]),
                                                        "required": .array([
                                                            .string("baseline_usd"),
                                                            .string("free_rows"),
                                                            .string("max_rows_ceiling"),
                                                            .string("row_cpm_usd"),
                                                        ]),
                                                        "additionalProperties": .bool(false),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "manifest": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("array"),
                                                        "items": .object([
                                                            "type": .string("object"),
                                                            "properties": .object([
                                                                "dtype": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("boolean"),
                                                                                .string("date"),
                                                                                .string("datetime"),
                                                                                .string("number"),
                                                                                .string("string"),
                                                                            ]),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "entity": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "metric": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "name": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "unit": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                            "required": .array([]),
                                                            "additionalProperties": .bool(false),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                        ]),
                                        "required": .array([]),
                                        "additionalProperties": .object([:]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "exportable": .object([
                                "type": .string("boolean"),
                            ]),
                            "nodes": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "id": .object([
                                                    "type": .string("string"),
                                                ]),
                                                "type": .object([
                                                    "type": .string("string"),
                                                    "enum": .array([
                                                        .string("entity"),
                                                        .string("metric"),
                                                    ]),
                                                ]),
                                                "name": .object([
                                                    "type": .string("string"),
                                                ]),
                                                "description": .object([
                                                    "anyOf": .array([
                                                        .object([
                                                            "type": .string("string"),
                                                        ]),
                                                        .object([
                                                            "type": .string("null"),
                                                        ]),
                                                    ]),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("id"),
                                                .string("type"),
                                                .string("name"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "metric_definitions": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "name": .object([
                                                    "type": .string("string"),
                                                ]),
                                                "definition": .object([
                                                    "type": .string("string"),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("name"),
                                                .string("definition"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "data_freshness": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("object"),
                                        "properties": .object([
                                            "coverage_end": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "data_as_of": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "last_updated": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                        ]),
                                        "required": .array([]),
                                        "additionalProperties": .bool(false),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                        ]),
                        "required": .array([]),
                        "additionalProperties": .object([:]),
                    ]),
                ]),
                "web_results": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string"),
                            ]),
                            "url": .object([
                                "type": .string("string"),
                            ]),
                            "snippet": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "source_name": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "publish_date": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("string"),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                            "content": .object([
                                "anyOf": .array([
                                    .object([
                                        "type": .string("object"),
                                        "properties": .object([
                                            "content_format": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                        "enum": .array([
                                                            .string("card_json"),
                                                            .string("csv"),
                                                            .string("json_compact"),
                                                            .string("json_records"),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "cost": .object([
                                                "type": .string("number"),
                                            ]),
                                            "data": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "records": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("array"),
                                                        "items": .object([
                                                            "type": .string("object"),
                                                            "additionalProperties": .object([
                                                                "anyOf": .array([
                                                                    .object([
                                                                        "anyOf": .array([
                                                                            .object([
                                                                                "type": .string("boolean"),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("number"),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("string"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    .object([
                                                                        "type": .string("null"),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "dataset": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([
                                                            "columns": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("object"),
                                                                    "properties": .object([
                                                                        "name": .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        "type": .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("boolean"),
                                                                                .string("date"),
                                                                                .string("datetime"),
                                                                                .string("number"),
                                                                                .string("string"),
                                                                            ]),
                                                                        ]),
                                                                        "unit": .object([
                                                                            "anyOf": .array([
                                                                                .object([
                                                                                    "type": .string("string"),
                                                                                ]),
                                                                                .object([
                                                                                    "type": .string("null"),
                                                                                ]),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    "required": .array([
                                                                        .string("name"),
                                                                        .string("type"),
                                                                    ]),
                                                                    "additionalProperties": .bool(false),
                                                                ]),
                                                            ]),
                                                            "rows": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("array"),
                                                                    "items": .object([
                                                                        "anyOf": .array([
                                                                            .object([
                                                                                "anyOf": .array([
                                                                                    .object([
                                                                                        "type": .string("boolean"),
                                                                                    ]),
                                                                                    .object([
                                                                                        "type": .string("number"),
                                                                                    ]),
                                                                                    .object([
                                                                                        "type": .string("string"),
                                                                                    ]),
                                                                                ]),
                                                                            ]),
                                                                            .object([
                                                                                "type": .string("null"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                            "total_rows": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "truncated": .object([
                                                                "type": .string("boolean"),
                                                            ]),
                                                            "ref": .object([
                                                                "type": .string("string"),
                                                            ]),
                                                            "sources": .object([
                                                                "type": .string("array"),
                                                                "items": .object([
                                                                    "type": .string("object"),
                                                                    "properties": .object([
                                                                        "name": .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        "index": .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("data"),
                                                                                .string("web"),
                                                                            ]),
                                                                        ]),
                                                                    ]),
                                                                    "required": .array([
                                                                        .string("name"),
                                                                    ]),
                                                                    "additionalProperties": .bool(false),
                                                                ]),
                                                            ]),
                                                            "provenance": .object([
                                                                "type": .string("string"),
                                                                "enum": .array([
                                                                    .string("query"),
                                                                    .string("web_extraction"),
                                                                ]),
                                                            ]),
                                                        ]),
                                                        "required": .array([
                                                            .string("columns"),
                                                            .string("rows"),
                                                            .string("total_rows"),
                                                            .string("truncated"),
                                                            .string("ref"),
                                                            .string("sources"),
                                                        ]),
                                                        "additionalProperties": .bool(false),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "card_data": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([:]),
                                                        "required": .array([]),
                                                        "additionalProperties": .object([:]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "card_data_schema": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([:]),
                                                        "required": .array([]),
                                                        "additionalProperties": .object([:]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "url": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "expires_at": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("string"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "total_rows": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("number"),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "truncated": .object([
                                                "type": .string("boolean"),
                                            ]),
                                            "export_pricing": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("object"),
                                                        "properties": .object([
                                                            "baseline_usd": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "free_rows": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "max_rows_ceiling": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                            "row_cpm_usd": .object([
                                                                "type": .string("number"),
                                                            ]),
                                                        ]),
                                                        "required": .array([
                                                            .string("baseline_usd"),
                                                            .string("free_rows"),
                                                            .string("max_rows_ceiling"),
                                                            .string("row_cpm_usd"),
                                                        ]),
                                                        "additionalProperties": .bool(false),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                            "manifest": .object([
                                                "anyOf": .array([
                                                    .object([
                                                        "type": .string("array"),
                                                        "items": .object([
                                                            "type": .string("object"),
                                                            "properties": .object([
                                                                "dtype": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                            "enum": .array([
                                                                                .string("boolean"),
                                                                                .string("date"),
                                                                                .string("datetime"),
                                                                                .string("number"),
                                                                                .string("string"),
                                                                            ]),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "entity": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "metric": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "name": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                                "unit": .object([
                                                                    "anyOf": .array([
                                                                        .object([
                                                                            "type": .string("string"),
                                                                        ]),
                                                                        .object([
                                                                            "type": .string("null"),
                                                                        ]),
                                                                    ]),
                                                                ]),
                                                            ]),
                                                            "required": .array([]),
                                                            "additionalProperties": .bool(false),
                                                        ]),
                                                    ]),
                                                    .object([
                                                        "type": .string("null"),
                                                    ]),
                                                ]),
                                            ]),
                                        ]),
                                        "required": .array([]),
                                        "additionalProperties": .object([:]),
                                    ]),
                                    .object([
                                        "type": .string("null"),
                                    ]),
                                ]),
                            ]),
                        ]),
                        "required": .array([
                            .string("title"),
                            .string("url"),
                        ]),
                        "additionalProperties": .object([:]),
                    ]),
                ]),
                "usage": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "total_cost_usd": .object([
                                    "type": .string("number"),
                                ]),
                                "compute": .object([
                                    "anyOf": .array([
                                        .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "cost_usd": .object([
                                                    "type": .string("number"),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("cost_usd"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                        .object([
                                            "type": .string("null"),
                                        ]),
                                    ]),
                                ]),
                                "data": .object([
                                    "anyOf": .array([
                                        .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "cost_usd": .object([
                                                    "type": .string("number"),
                                                ]),
                                                "datasets": .object([
                                                    "type": .string("number"),
                                                ]),
                                            ]),
                                            "required": .array([
                                                .string("cost_usd"),
                                                .string("datasets"),
                                            ]),
                                            "additionalProperties": .bool(false),
                                        ]),
                                        .object([
                                            "type": .string("null"),
                                        ]),
                                    ]),
                                ]),
                            ]),
                            "required": .array([
                                .string("total_cost_usd"),
                            ]),
                            "additionalProperties": .bool(false),
                        ]),
                        .object([
                            "type": .string("null"),
                        ]),
                    ]),
                ]),
                "related": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("object"),
                                "properties": .object([:]),
                                "required": .array([]),
                                "additionalProperties": .object([:]),
                            ]),
                        ]),
                        .object([
                            "type": .string("null"),
                        ]),
                    ]),
                ]),
            ]),
            "required": .array([
                .string("request_id"),
            ]),
            "additionalProperties": .object([:]),
        ]),
        .object([
            "type": .string("object"),
            "properties": .object([
                "error": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("api_error"),
                        .string("configuration_error"),
                        .string("execution_error"),
                        .string("invalid_input"),
                        .string("rate_limit"),
                        .string("timeout"),
                        .string("unknown_tool"),
                    ]),
                ]),
                "statusCode": .object([
                    "type": .string("number"),
                ]),
                "message": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([
                .string("error"),
                .string("message"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])
