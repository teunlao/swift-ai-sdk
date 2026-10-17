import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayTools")
struct GatewayToolsTests {
    @Test("Browserbase search validates provider query and result limits")
    func browserbaseSearchValidation() async throws {
        let schema = asSchema(gatewayTools.browserbaseSearch().inputSchema)
        let valid: JSONValue = ["query": "Swift concurrency", "num_results": 25]
        #expect(await schema.validate(valid).value == valid)
        #expect(await schema.validate(["query": "Swift", "num_results": 26] as JSONValue).error != nil)
        #expect(await schema.validate(["query": "", "num_results": 1] as JSONValue).error != nil)
    }

    @Test("Browserbase fetch parses raw and structured page content")
    func browserbaseFetchContent() async throws {
        let tool = gatewayTools.browserbaseFetch(.init(format: .json, schema: ["type": "object"]))
        let schema = asSchema(try #require(tool.outputSchema))
        let result: JSONValue = [
            "id": "fetch_1", "content": ["price": 12], "contentType": "application/json",
            "encoding": "utf-8", "headers": ["x-source": "origin"], "statusCode": 200,
        ]
        #expect(await schema.validate(result).value == result)
        #expect(await schema.validate([
            "id": "fetch_2", "content": "Page", "contentType": "text/plain",
            "encoding": "utf-8", "headers": [:], "statusCode": 200,
        ] as JSONValue).value != nil)
        #expect(await schema.validate(["id": "fetch_3", "content": []] as JSONValue).error != nil)
    }

    @Test("Exa validates nested extraction controls and search errors")
    func exaContentValidation() async throws {
        let tool = gatewayTools.exaSearch()
        let input: JSONValue = [
            "query": "Swift release", "type": "instant",
            "contents": ["text": ["verbosity": "compact", "include_sections": ["body"]], "highlights": true],
        ]
        #expect(await asSchema(tool.inputSchema).validate(input).value == input)
        #expect(await asSchema(tool.inputSchema).validate([
            "query": "Swift", "contents": ["text": ["verbosity": "invalid"]],
        ] as JSONValue).error != nil)
        let output = asSchema(try #require(tool.outputSchema))
        let error: JSONValue = ["error": "configuration_error", "statusCode": 401, "message": "Missing credential"]
        #expect(await output.validate(error).value == error)
        let response: JSONValue = [
            "requestId": "exa_1", "results": [["id": "page_1", "title": "Release", "url": "https://example.com", "service_field": true]],
            "service_field": "ignored",
        ]
        #expect(await output.validate(response).value == [
            "requestId": "exa_1", "results": [["id": "page_1", "title": "Release", "url": "https://example.com"]],
        ])
    }

    @Test("Tako preserves dataset cells and service extensions while validating dataset shape")
    func takoDatasetValidation() async throws {
        let schema = asSchema(try #require(gatewayTools.takoSearch().outputSchema))
        let result: JSONValue = [
            "request_id": "request_1",
            "cards": [["content": ["dataset": [
                "columns": [["name": "revenue", "type": "number"]],
                "rows": [[true, 12, "USD", nil]], "total_rows": 1, "truncated": false,
                "ref": "dataset_1", "sources": [["name": "report", "index": "data"]],
            ], "new_field": true], "service_annotation": "kept"]],
            "new_top_level": ["enabled": true],
        ]
        #expect(await schema.validate(result).value == result)
        let invalid: JSONValue = [
            "request_id": "request_2",
            "cards": [["content": ["dataset": [
                "columns": [["name": "revenue", "type": "number"]],
                "rows": [[["invalid": true]]], "total_rows": 1, "truncated": false,
                "ref": "dataset_1", "sources": [],
            ]]]],
        ]
        #expect(await schema.validate(invalid).error != nil)
    }

    @Test("parallelSearch tool factory produces provider tool with encoded args")
    func parallelSearchFactory() async throws {
        let tool = gatewayTools.parallelSearch()
        #expect(tool.type == .provider)
        #expect(tool.id == "gateway.parallel_search")
        #expect(tool.name == "parallel_search")
        #expect(tool.args == [:])
        #expect(tool.outputSchema != nil)

        let configured = gatewayTools.parallelSearch(.init(
            mode: .agentic,
            maxResults: 7,
            sourcePolicy: .init(
                includeDomains: ["wikipedia.org"],
                excludeDomains: ["reddit.com"],
                afterDate: "2024-01-01"
            ),
            excerpts: .init(maxCharsPerResult: 200, maxCharsTotal: 2000),
            fetchPolicy: .init(maxAgeSeconds: 0)
        ))

        guard let args = configured.args else {
            Issue.record("Expected args")
            return
        }

        #expect(args["mode"] == .string("agentic"))
        #expect(args["maxResults"] == .number(7))

        if case .object(let source)? = args["sourcePolicy"] {
            #expect(source["includeDomains"] == .array([.string("wikipedia.org")]))
            #expect(source["excludeDomains"] == .array([.string("reddit.com")]))
            #expect(source["afterDate"] == .string("2024-01-01"))
        } else {
            Issue.record("Expected sourcePolicy object")
        }

        if case .object(let excerpts)? = args["excerpts"] {
            #expect(excerpts["maxCharsPerResult"] == .number(200))
            #expect(excerpts["maxCharsTotal"] == .number(2000))
        } else {
            Issue.record("Expected excerpts object")
        }

        if case .object(let fetchPolicy)? = args["fetchPolicy"] {
            #expect(fetchPolicy["maxAgeSeconds"] == .number(0))
        } else {
            Issue.record("Expected fetchPolicy object")
        }
    }

    @Test("perplexitySearch tool factory produces provider tool with encoded args")
    func perplexitySearchFactory() async throws {
        let tool = gatewayTools.perplexitySearch()
        #expect(tool.type == .provider)
        #expect(tool.id == "gateway.perplexity_search")
        #expect(tool.name == "perplexity_search")
        #expect(tool.args == [:])
        #expect(tool.outputSchema != nil)

        let configured = gatewayTools.perplexitySearch(.init(
            maxResults: 10,
            maxTokensPerPage: 2048,
            maxTokens: 25_000,
            country: "US",
            searchDomainFilter: ["nature.com", "-spam.net"],
            searchLanguageFilter: ["en"],
            searchRecencyFilter: .week
        ))

        guard let args = configured.args else {
            Issue.record("Expected args")
            return
        }

        #expect(args["maxResults"] == .number(10))
        #expect(args["maxTokensPerPage"] == .number(2048))
        #expect(args["maxTokens"] == .number(25_000))
        #expect(args["country"] == .string("US"))
        #expect(args["searchDomainFilter"] == .array([.string("nature.com"), .string("-spam.net")]))
        #expect(args["searchLanguageFilter"] == .array([.string("en")]))
        #expect(args["searchRecencyFilter"] == .string("week"))
    }
}

