import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses non-stream response contracts")
struct OpenAIResponsesResponseContractTests {
    private func generate(_ value: JSONValue, logprobs: Bool = false) async throws -> LanguageModelV4GenerateResult {
        let data = try JSONEncoder().encode(value)
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "X-Request-Id": "response-contract"]
            )!)
        }))
        return try await provider.responses("gpt-4.1").doGenerate(options: .init(
            prompt: [], providerOptions: ["openai": ["logprobs": .bool(logprobs)]]
        ))
    }

    @Test("Malformed modeled responses fail with HTTP diagnostics", arguments: [
        JSONValue.object(["id": .null, "output": .array([])]),
        .object(["output": .array([.object(["type": .string("function_call"), "id": .string("fc"), "call_id": .string("call"), "name": .string("lookup"), "arguments": .number(1)])])]),
        .object(["output": .array([.object(["type": .string("message"), "role": .string("assistant"), "id": .string("msg"), "content": .array([.object(["type": .string("output_text"), "text": .string("x"), "annotations": .array([.object(["type": .string("url_citation"), "url": .string("https://example.com"), "title": .string("Source")])])])])])])]),
        .object(["output": .array([.object(["type": .string("future_output"), "id": .string("future")])])])
    ])
    func malformedResponse(value: JSONValue) async throws {
        do {
            _ = try await generate(value)
            Issue.record("Expected invalid-response failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
            #expect(error.responseHeaders?["x-request-id"] == "response-contract")
            let text = try #require(error.responseBody)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) == value)
        }
    }

    @Test("Known-field projection leaves the original HTTP response intact")
    func projectedFieldsAndRawResponse() async throws {
        let projected: JSONValue = .object([
            "token": .string("x"), "logprob": .number(-0.5),
            "top_logprobs": .array([.object(["token": .string("x"), "logprob": .number(-0.5)])])
        ])
        let rawLogprob: JSONValue = .object([
            "token": .string("x"), "logprob": .number(-0.5), "bytes": .array([.number(120)]),
            "top_logprobs": .array([.object(["token": .string("x"), "logprob": .number(-0.5), "extra": .bool(true)])])
        ])
        let response: JSONValue = .object([
            "debug": .object(["request": .string("original")]),
            "output": .array([.object([
                "type": .string("message"), "role": .string("assistant"), "id": .string("msg"), "phase": .null,
                "content": .array([.object(["type": .string("output_text"), "text": .string("x"), "annotations": .array([]), "logprobs": .array([rawLogprob])])])
            ])])
        ])
        let result = try await generate(response, logprobs: true)
        #expect(result.providerMetadata?["openai"]?["logprobs"] == .array([.array([projected])]))
        #expect(result.content.contains { if case .text(let text) = $0 { return text.text == "x" }; return false })
        #expect(try jsonValue(from: #require(result.response?.body)) == response)
    }

    @Test("Failed web searches return provider tool errors", arguments: ["failed", "incomplete"])
    func webSearchFailure(status: String) async throws {
        let result = try await generate(.object(["output": .array([.object([
            "type": .string("web_search_call"), "id": .string("search"), "status": .string(status),
            "action": .object(["type": .string("search"), "queries": .array([.string("weather")])])
        ])])]))
        let toolResult = try #require(result.content.compactMap { part -> LanguageModelV4ToolResult? in
            if case .toolResult(let value) = part { return value }; return nil
        }.first)
        #expect(toolResult.toolCallId == "search")
        #expect(toolResult.toolName == "web_search")
        #expect(toolResult.isError == true)
        #expect(toolResult.result == .object(["status": .string(status)]))
    }

    @Test("Usage retains future fields and null versus absent details", arguments: [true, false])
    func rawUsage(withNullDetails: Bool) async throws {
        var usage: [String: JSONValue] = [
            "input_tokens": .number(5), "output_tokens": .number(3), "total_tokens": .number(8.5),
            "future_meter": .object(["units": .number(2.5)]),
            "output_tokens_details": .object(["reasoning_tokens": .number(1), "orchestration_output_tokens": .number(0.5), "future": .null])
        ]
        if withNullDetails { usage["input_tokens_details"] = .null }
        let result = try await generate(.object(["output": .array([]), "usage": .object(usage)]))
        #expect(result.usage.raw == .object(usage))
        #expect(result.usage.inputTokens.total == 5)
        #expect(result.usage.inputTokens.noCache == 5)
        #expect(result.usage.outputTokens.text == 2)
        #expect(result.usage.outputTokens.reasoning == 1)
    }

    @Test("Usage refuses values outside the core Int representation", arguments: [(1.5, 0.0), (1e20, 0.0), (-9e18, 9e18)])
    func coreUsageBoundary(input: Double, cached: Double) async throws {
        do {
            _ = try await generate(.object(["output": .array([]), "usage": .object([
                "input_tokens": .number(input), "output_tokens": .number(1),
                "input_tokens_details": .object(["cached_tokens": .number(cached)])
            ])]))
            Issue.record("Expected core usage representation failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("Provider errors and missing output preserve raw response diagnostics", arguments: [true, false])
    func responseRefusal(providerError: Bool) async throws {
        var response: [String: JSONValue] = ["id": .string("resp"), "debug": .string("kept")]
        if providerError {
            response["error"] = .object(["message": .string("Rejected"), "type": .string("invalid_request_error"), "code": .string("invalid_request"), "param": .null])
        } else {
            response["incomplete_details"] = .object(["reason": .string("max_output_tokens")])
        }
        do {
            _ = try await generate(.object(response))
            Issue.record("Expected Responses refusal")
        } catch let error as APICallError {
            #expect(error.statusCode == (providerError ? 400 : 500))
            #expect(error.isRetryable == false)
            #expect(error.responseHeaders?["x-request-id"] == "response-contract")
            let body = try #require(error.responseBody)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)) == .object(response))
        }
    }
}
