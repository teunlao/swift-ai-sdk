import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import MistralProvider

@Suite("Mistral chat V4 contracts")
struct MistralChatContractTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]

    @Test("maps reasoning and sampling options and preserves detailed usage")
    func reasoningAndUsage() async throws {
        let recorder = RequestRecorder()
        let fetch: FetchFunction = { request in
            await recorder.record(request)
            let body = #"{"object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"error"}],"usage":{"prompt_tokens":40,"completion_tokens":8,"total_tokens":48,"num_cached_tokens":15,"prompt_tokens_details":{"cached_tokens":20,"messages":[{}],"custom":7},"completion_tokens_details":{"reasoning_tokens":4},"service_tier":"auto","extension":true}}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).chat(modelId: "future-model")
        let result = try await model.doGenerate(options: .init(
            prompt: prompt, stopSequences: ["end"], presencePenalty: 0.2, frequencyPenalty: 0.3, reasoning: .low,
            providerOptions: ["mistral": ["promptCacheKey": "shared-prefix", "documentPageLimit": 2.5]]
        ))
        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["reasoning_effort"] as? String == "high")
        #expect(body["frequency_penalty"] as? Double == 0.3)
        #expect(body["presence_penalty"] as? Double == 0.2)
        #expect(body["stop"] as? [String] == ["end"])
        #expect(body["prompt_cache_key"] as? String == "shared-prefix")
        #expect(body["document_page_limit"] as? Double == 2.5)
        #expect(result.warnings == [.compatibility(feature: "reasoning", details: #"reasoning "low" is not directly supported by this model. mapped to effort "high"."#)])
        #expect(result.finishReason.unified == .error)
        #expect(result.usage.inputTokens.noCache == 25)
        #expect(result.usage.inputTokens.cacheRead == 15)
        #expect(result.usage.outputTokens.text == 8)
        guard case .object(let raw) = result.usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(raw["extension"] == true)
        #expect(raw["service_tier"] == "auto")
    }

    @Test("non-reasoning models omit unsupported reasoning configuration")
    func unsupportedReasoning() async throws {
        let recorder = RequestRecorder()
        let fetch: FetchFunction = { request in
            await recorder.record(request)
            let body = #"{"object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).chat(modelId: .mistralLargeLatest)
        let result = try await model.doGenerate(options: .init(prompt: prompt, reasoning: .high, providerOptions: ["mistral": ["reasoningEffort": "high"]]))
        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["reasoning_effort"] == nil)
        #expect(result.content == [.text(.init(text: "ok"))])
        #expect(result.warnings == [.unsupported(feature: "reasoning", details: "This model does not support reasoning configuration.")])
    }

    @Test("joins incremental tool calls and reports cached stream usage")
    func incrementalTools() async throws {
        let fetch: FetchFunction = { request in
            let events = [
                #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"weather","arguments":"{\"city\":"}}]}}]}"#,
                #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"Paris\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":4,"total_tokens":16,"prompt_token_details":{"cached_tokens":5}}}"#
            ]
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for event in events { continuation.yield(Data("data: \(event)\n\n".utf8)) }
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).chat(modelId: .mistralSmallLatest)
        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collectStream(result.stream)
        #expect(parts.filter { if case .toolInputStart = $0 { true } else { false } }.count == 1)
        #expect(parts.compactMap { if case .toolInputDelta(_, let delta, _) = $0 { delta } else { nil } }.joined() == #"{"city":"Paris"}"#)
        #expect(parts.contains(.toolCall(.init(toolCallId: "call-1", toolName: "weather", input: #"{"city":"Paris"}"#))))
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .toolCalls)
        #expect(usage.inputTokens.noCache == 7)
        #expect(usage.inputTokens.cacheRead == 5)
    }

    @Test("embedding provider dimensions override top-level dimensions and invalid dimensions are refused")
    func embeddingOptions() async throws {
        let recorder = RequestRecorder()
        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return FetchResponse(body: .data(Data(#"{"data":[{"embedding":[1,2]}]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).embedding(.codestralEmbed)
        let result = try await model.doEmbed(options: .init(values: ["code"], dimensions: 3, providerOptions: ["mistral": ["metadata": ["purpose": "search"], "outputDimension": 2, "outputDtype": "int8"]]))
        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["output_dimension"] as? Int == 2)
        #expect(body["output_dtype"] as? String == "int8")
        #expect(body["metadata"] as? [String: String] == ["purpose": "search"])
        #expect(result.embeddings == [[1, 2]])
        for dimension in [JSONValue.number(0), .number(9_007_199_254_740_992)] {
            await #expect(throws: InvalidArgumentError.self) {
                try await model.doEmbed(options: .init(values: ["code"], providerOptions: ["mistral": ["outputDimension": dimension]]))
            }
        }
    }

    @Test("rejects malformed reference IDs in a generation response")
    func invalidReference() async throws {
        let fetch: FetchFunction = { request in
            let body = #"{"object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":[{"type":"reference","reference_ids":[true]}]}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).chat(modelId: .mistralSmallLatest)
        await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(prompt: prompt)) }
    }

    @Test("reports invalid image content as a stream parse error")
    func invalidStreamImage() async throws {
        let fetch: FetchFunction = { request in
            let body = #"{"choices":[{"index":0,"delta":{"content":[{"type":"image_url","image_url":{}}]}}]}"#
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data("data: \(body)\n\n".utf8))
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let model = createMistral(settings: .init(apiKey: "key", fetch: fetch)).chat(modelId: .mistralSmallLatest)
        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collectStream(result.stream)
        #expect(parts.contains { if case .error(.error(let error)) = $0 { error is TypeValidationError } else { false } })
    }
}
