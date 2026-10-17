import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AlibabaProvider

@Suite("Alibaba chat public contracts")
struct AlibabaChatLanguageModelTests {
    @Test("generation preserves text reasoning tools and loose cache usage")
    func generation() async throws {
        let usage: JSONValue = ["prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150,
                                "prompt_tokens_details": ["cached_tokens": 60, "cache_creation_input_tokens": 20, "cache_type": "explicit", "future": true],
                                "completion_tokens_details": ["reasoning_tokens": 70], "extra": 1.5]
        var response = alibabaTestResponse
        response["usage"] = usage
        response["choices"] = [["index": 0, "message": ["role": "assistant", "content": "Answer", "reasoning_content": "Thinking", "tool_calls": [["id": "call", "type": "function", "function": ["name": "lookup", "arguments": "{}"]]]], "finish_reason": "tool_calls"]]
        let endpoint = AlibabaTestEndpoint(.object(response))
        let result = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: alibabaTestPrompt))
        #expect(result.content == [.text(.init(text: "Answer")), .reasoning(.init(text: "Thinking")), .toolCall(.init(toolCallId: "call", toolName: "lookup", input: "{}"))])
        #expect(result.finishReason == .init(unified: .toolCalls, raw: "tool_calls"))
        #expect(result.usage.inputTokens.noCache == 20)
        #expect(result.usage.inputTokens.cacheWrite == 20)
        #expect(result.usage.outputTokens.text == 0)
        #expect(result.usage.raw == usage)
        #expect(result.response?.id == "chat-1")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 1000))
        let sent = try await endpoint.body()
        #expect(sent == ["model": "qwen-plus", "messages": [["role": "user", "content": [["type": "text", "text": "Hello"]]]]])
        let request = try #require(result.request?.body as? String)
        #expect(try JSONDecoder().decode(JSONObject.self, from: Data(request.utf8)) == sent)
    }

    @Test("supported model prefixes use JSON schema while other models use instructed JSON object", arguments: ["qwen-plus", "qwen3.7-max", "qwen3.8-flash-latest"])
    func structuredOutput(id: String) async throws {
        let endpoint = AlibabaTestEndpoint()
        let result = try await alibabaTestModel(endpoint, id: .init(rawValue: id)).doGenerate(options: .init(prompt: alibabaTestPrompt, responseFormat: .json(schema: ["type": "object"], name: "answer", description: "schema")))
        let body = try await endpoint.body()
        if id == "qwen-plus" {
            #expect(body["response_format"] == ["type": "json_object"])
            guard case .array(let messages) = body["messages"], case .object(let first) = messages.first else { Issue.record("Missing JSON instruction message"); return }
            #expect(first["role"] == "system")
            #expect(result.warnings.contains { if case .compatibility(let feature, _) = $0 { feature == "responseFormat JSON schema" } else { false } })
        } else {
            #expect(body["response_format"] == ["type": "json_schema", "json_schema": ["schema": ["type": "object"], "name": "answer", "description": "schema"]])
            #expect(result.warnings.isEmpty)
        }
    }

    @Test("native thinking options override generic reasoning and strict function tools serialize", arguments: [false, true])
    func thinkingOverride(explicit: Bool) async throws {
        let endpoint = AlibabaTestEndpoint()
        let settings: JSONObject = explicit ? ["enableThinking": true, "thinkingBudget": 100, "parallelToolCalls": false] : [:]
        let result = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: alibabaTestPrompt,
            tools: [.function(.init(name: "lookup", inputSchema: ["type": "object"], strict: false))], toolChoice: .required,
            reasoning: LanguageModelV4ReasoningEffort.none, providerOptions: ["alibaba": settings]))
        let body = try await endpoint.body()
        #expect(body["enable_thinking"] == .bool(explicit))
        #expect(body["thinking_budget"] == (explicit ? .number(100) : Optional<JSONValue>.none))
        #expect(body["parallel_tool_calls"] == (explicit ? .bool(false) : Optional<JSONValue>.none))
        #expect(body["tools"] == [["type": "function", "function": ["name": "lookup", "parameters": ["type": "object"], "strict": false]]])
        #expect(body["tool_choice"] == "required")
        #expect(result.content == [.text(.init(text: "Answer"))])
    }

    @Test("stream transitions close text and reasoning before complete incremental tools")
    func streaming() async throws {
        let events: [JSONValue] = [
            ["id": "stream", "created": 1000, "model": "qwen-plus", "choices": [["index": 0, "delta": ["content": "Lead"]]]],
            ["choices": [["index": 0, "delta": ["reasoning_content": "Thought"]]]],
            ["choices": [["index": 0, "delta": ["content": "Tail"]]]],
            ["choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "id": "call", "type": "function", "function": ["name": "lookup", "arguments": "{\"x\":" ]]]]]]],
            ["choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "function": ["arguments": "1}"]]]], "finish_reason": "tool_calls"]]],
            ["choices": [], "usage": ["prompt_tokens": 10, "completion_tokens": 3, "total_tokens": 13]]
        ]
        let endpoint = AlibabaTestEndpoint(events: events)
        let result = try await alibabaTestModel(endpoint).doStream(options: .init(prompt: alibabaTestPrompt, includeRawChunks: true))
        let parts = try await collectAlibaba(result.stream)
        let starts = parts.compactMap { if case .reasoningStart(let id, _) = $0 { id } else { nil } }
        let id = try #require(starts.first)
        #expect(parts.contains(.reasoningDelta(id: id, delta: "Thought", providerMetadata: nil)))
        #expect(parts.contains(.reasoningEnd(id: id, providerMetadata: nil)))
        #expect(parts.filter { if case .textEnd = $0 { true } else { false } }.count == 2)
        #expect(parts.compactMap { if case .textDelta(_, let text, _) = $0 { text } else { nil } }.joined() == "LeadTail")
        #expect(parts.contains(.toolCall(.init(toolCallId: "call", toolName: "lookup", input: #"{"x":1}"#))))
        #expect(parts.filter { if case .raw = $0 { true } else { false } }.count == events.count)
        guard case .finish(let finish, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish.unified == .toolCalls)
        #expect(usage.inputTokens.total == 10)
        #expect(try await endpoint.body()["stream_options"] == ["include_usage": true])
    }

    @Test("invalid provider options refuse before an API request")
    func invalidOptions() async throws {
        let model = alibabaTestModel(AlibabaTestEndpoint())
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(prompt: alibabaTestPrompt, providerOptions: ["alibaba": ["preserveThinking": .null]])) }
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(prompt: alibabaTestPrompt, providerOptions: ["alibaba": ["thinkingBudget": 0]])) }
    }
}
