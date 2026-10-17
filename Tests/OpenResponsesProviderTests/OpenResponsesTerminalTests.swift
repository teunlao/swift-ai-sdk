import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenResponsesProvider

@Suite("Open Responses terminal boundaries")
struct OpenResponsesTerminalTests {
    struct FinishCase: Sendable {
        let reason: String?
        let tools: Bool
        let expected: LanguageModelV4FinishReason.Unified
    }
    @Test("generation maps protocol finish reasons and actual tool calls", arguments: [
        FinishCase(reason: nil, tools: false, expected: .stop), FinishCase(reason: nil, tools: true, expected: .toolCalls),
        FinishCase(reason: "max_output_tokens", tools: false, expected: .length), FinishCase(reason: "content_filter", tools: false, expected: .contentFilter),
        FinishCase(reason: "other", tools: false, expected: .other), FinishCase(reason: "other", tools: true, expected: .toolCalls)
    ])
    func generationFinish(value: FinishCase) async throws {
        var response = openResponsesTestResponse(output: value.tools ? [["type": "function_call", "id": "item", "call_id": "call", "name": "tool", "arguments": "{}"]] : [])
        if let reason = value.reason { response["incomplete_details"] = ["reason": .string(reason)] }
        let endpoint = OpenResponsesTestEndpoint(response)
        let provider = try openResponsesProvider(endpoint)
        let result = try await provider("model").doGenerate(options: .init(prompt: []))
        #expect(result.finishReason == .init(unified: value.expected, raw: value.reason))
        #expect(result.usage.inputTokens.noCache == 0)
        #expect(result.usage.outputTokens.text == 0)
    }

    @Test("missing output is a non-retryable API failure with raw response diagnostics")
    func missingOutput() async throws {
        let payload: JSONObject = ["status": "cancelled", "incomplete_details": ["reason": "request-ended"]]
        let endpoint = OpenResponsesTestEndpoint(payload)
        let provider = try openResponsesProvider(endpoint)
        do {
            _ = try await provider("model").doGenerate(options: .init(prompt: []))
            Issue.record("Expected no-output failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 500)
            #expect(error.isRetryable == false)
            let raw = try JSONDecoder().decode(JSONObject.self, from: Data(#require(error.responseBody).utf8))
            #expect(raw == payload)
            #expect(error.message.contains("request-ended"))
        }
    }

    @Test("completed and incomplete stream events preserve finish reasons and usage", arguments: ["response.completed", "response.incomplete"])
    func streamFinish(type: String) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let details: JSONValue = type == "response.incomplete" ? ["reason": "max_output_tokens"] : .null
        let usage: JSONValue = ["input_tokens": 10, "output_tokens": 4, "input_tokens_details": ["cached_tokens": 2, "cache_write_tokens": 3], "output_tokens_details": ["reasoning_tokens": 1], "extra": true]
        try await endpoint.setEvents([["type": .string(type), "response": ["incomplete_details": details, "usage": usage]]])
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        guard case .finish(let reason, let result, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == (type == "response.incomplete" ? .length : .stop))
        #expect(result.inputTokens.noCache == 5)
        #expect(result.inputTokens.cacheWrite == 3)
        #expect(result.outputTokens.text == 3)
        #expect(result.raw == usage)
    }

    @Test("JSON null stream chunks fail at the native boundary instead of finishing successfully")
    func nullChunk() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        try await endpoint.setEvents([.null])
        let provider = try openResponsesProvider(endpoint)
        let result = try await provider("model").doStream(options: .init(prompt: []))
        await #expect(throws: InvalidResponseDataError.self) { _ = try await openResponsesCollect(result) }
    }

    @Test("unknown wire values remain available through the raw path", arguments: [JSONValue.string("future"), .number(1), ["type": "endpoint.future", "payload": ["kept": true]]])
    func rawUnknown(value: JSONValue) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        try await endpoint.setEvents([value])
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [], includeRawChunks: true)))
        #expect(parts == [.streamStart(warnings: []), .raw(rawValue: value), .finish(finishReason: .init(unified: .other), usage: .init(), providerMetadata: nil)])
    }

    @Test("cancellation propagates through generation and streaming API calls", arguments: [false, true])
    func cancellation(stream: Bool) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        await #expect(throws: CancellationError.self) {
            if stream { _ = try await provider("model").doStream(options: .init(prompt: [], abortSignal: { true })) }
            else { _ = try await provider("model").doGenerate(options: .init(prompt: [], abortSignal: { true })) }
        }
    }
}
