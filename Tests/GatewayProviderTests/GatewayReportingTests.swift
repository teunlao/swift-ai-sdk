import Foundation
import Testing
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("Gateway reporting")
struct GatewayReportingTests {
    @Test("Spend reports encode every filter and decode prices and token usage")
    func spendReport() async throws {
        let response = #"{"results":[{"hour":"2026-10-16T01:00:00Z","credential_type":"byok","total_cost":0.125,"market_cost":0.25,"input_tokens":100,"output_tokens":20,"cached_input_tokens":5,"cache_creation_input_tokens":2,"reasoning_tokens":3,"request_count":1}]}"#
        let config = GatewayConfig(
            baseURL: "https://gateway.example.com:8443/api/ai?ignored=value",
            headers: { ["Authorization": "Bearer report-key"] },
            fetch: { request in
                let url = try #require(request.url)
                #expect(url.scheme == "https")
                #expect(url.port == 8443)
                #expect(url.path == "/v1/report")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer report-key")
                let query = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map {
                    ($0.name, $0.value ?? "")
                })
                #expect(query == [
                    "start_date": "2026-10-01", "end_date": "2026-10-16", "group_by": "day", "date_part": "hour",
                    "user_id": "user+1@example.com", "model": "anthropic/claude-sonnet-5.5", "provider": "anthropic",
                    "credential_type": "byok", "tags": "production,api",
                ])
                #expect(url.absoluteString.contains("user%2B1%40example.com"))
                let http = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                return FetchResponse(body: .data(Data(response.utf8)), urlResponse: http)
            }
        )
        let result = try await GatewaySpendReport(config: config).getSpendReport(.init(
            startDate: "2026-10-01", endDate: "2026-10-16", groupBy: .day, datePart: .hour,
            userId: "user+1@example.com", model: "anthropic/claude-sonnet-5.5", provider: "anthropic", credentialType: .byok,
            tags: ["production", "api"]
        ))
        let row = try #require(result.results.first)
        #expect(row.hour == "2026-10-16T01:00:00Z")
        #expect(row.credentialType == .byok)
        #expect(row.totalCost == 0.125)
        #expect(row.marketCost == 0.25)
        #expect(row.inputTokens == 100)
        #expect(row.outputTokens == 20)
        #expect(row.cachedInputTokens == 5)
        #expect(row.cacheCreationInputTokens == 2)
        #expect(row.reasoningTokens == 3)
        #expect(row.requestCount == 1)
    }

    @Test("a selected empty tag differs from an empty tag selection", arguments: [false, true])
    func emptyTagFilter(_ selectEmptyTag: Bool) async throws {
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            let url = try #require(request.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let tags = query.first { $0.name == "tags" }
            #expect(tags?.value == (selectEmptyTag ? "" : nil))
            let http = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return FetchResponse(body: .data(Data(#"{"results":[]}"#.utf8)), urlResponse: http)
        }))
        let result = try await provider.getSpendReport(.init(startDate: "2026-10-01", endDate: "2026-10-16", tags: selectEmptyTag ? [""] : []))
        #expect(result.results.isEmpty)
    }

    @Test("Generation details unwrap data and retain billing and native token usage")
    func generationInfo() async throws {
        let response = #"{"data":{"id":"gen_1","total_cost":0.01,"upstream_inference_cost":0.008,"usage":0.01,"created_at":"2026-10-16T01:00:00Z","model":"openai/gpt-6.1-sol","is_byok":true,"provider_name":"openai","streamed":true,"finish_reason":"stop","latency":12,"generation_time":42,"native_tokens_prompt":100,"native_tokens_completion":20,"native_tokens_reasoning":3,"native_tokens_cached":5,"native_tokens_cache_creation":2,"billable_web_search_calls":1}}"#
        let config = GatewayConfig(
            baseURL: "https://gateway.example.com/api/ai", headers: { ["Authorization": "Bearer generation-key"] },
            fetch: { request in
                let url = try #require(request.url)
                #expect(url.absoluteString == "https://gateway.example.com/v1/generation?id=gen%2B1%20%26%3F")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer generation-key")
                let http = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                return FetchResponse(body: .data(Data(response.utf8)), urlResponse: http)
            }
        )
        let result = try await GatewayGenerationInfoFetcher(config: config).getGenerationInfo(.init(id: "gen+1 &?"))
        #expect(result.id == "gen_1")
        #expect(result.totalCost == 0.01)
        #expect(result.upstreamInferenceCost == 0.008)
        #expect(result.usage == 0.01)
        #expect(result.createdAt == "2026-10-16T01:00:00Z")
        #expect(result.model == "openai/gpt-6.1-sol")
        #expect(result.isByok)
        #expect(result.providerName == "openai")
        #expect(result.streamed)
        #expect(result.finishReason == "stop")
        #expect(result.latency == 12)
        #expect(result.generationTime == 42)
        #expect(result.promptTokens == 100)
        #expect(result.completionTokens == 20)
        #expect(result.reasoningTokens == 3)
        #expect(result.cachedTokens == 5)
        #expect(result.cacheCreationTokens == 2)
        #expect(result.billableWebSearchCalls == 1)
    }

    @Test("Generation HTTP failures retain typed context")
    func generationFailure() async throws {
        let config = GatewayConfig(baseURL: "https://gateway.example.com/api/ai", headers: { [:] }, fetch: { request in
            let url = try #require(request.url)
            let http = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return FetchResponse(body: .data(Data(#"{"error":{"type":"not_found","message":"Unknown generation"},"generationId":"gen_missing"}"#.utf8)), urlResponse: http)
        })
        do {
            _ = try await GatewayGenerationInfoFetcher(config: config).getGenerationInfo(.init(id: "gen_missing"))
            Issue.record("Expected typed resource failure")
        } catch let error as GatewayNotFoundError {
            #expect(error.generationId == "gen_missing")
            #expect(!error.isRetryable)
        }
    }
}
