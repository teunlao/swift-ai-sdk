import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GroqProvider

@Suite("Groq chat V4 contracts")
struct GroqChatContractTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]
    private let tool = LanguageModelV4Tool.function(.init(name: "json", inputSchema: ["type": "object"]))

    private func model(
        id: GroqChatModelId = .gptOss20b,
        response: String = #"{"choices":[{"index":0,"message":{"content":"ok"},"finish_reason":"stop"}]}"#,
        events: [String]? = nil,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> GroqChatLanguageModel {
        createGroq(settings: .init(apiKey: "key", fetch: { request in
            try inspect(request)
            let body: ProviderHTTPResponseBody
            if let events {
                body = .stream(AsyncThrowingStream { continuation in
                    for event in events { continuation.yield(Data("data: \(event)\n\n".utf8)) }
                    continuation.finish()
                })
            } else { body = .data(Data(response.utf8)) }
            return FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": events == nil ? "application/json" : "text/event-stream"])!)
        })).chat(modelId: id)
    }

    @Test("JSON with function tools uses a collision-free response tool and restores text output", arguments: [false, true])
    func jsonTool(applicationCall: Bool) async throws {
        let application = applicationCall ? #",{"id":"app","type":"function","function":{"name":"json","arguments":"{}"}}"# : ""
        let response = #"{"choices":[{"index":0,"message":{"content":"ignored","reasoning":"thinking","tool_calls":[{"id":"answer","type":"function","function":{"name":"json_1","arguments":"{\"value\":42}"}}"# + application + #"]},"finish_reason":"tool_calls"}]}"#
        let instance = model(response: response) { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            guard case .object(let payload) = body, case .array(let tools) = payload["tools"] else { Issue.record("Missing tools"); return }
            #expect(payload["response_format"] == nil)
            #expect(payload["parallel_tool_calls"] == false)
            #expect(payload["tool_choice"] == "required")
            #expect(tools == [
                ["type": "function", "function": ["name": "json", "parameters": ["type": "object"]]],
                ["type": "function", "function": ["name": "json_1", "description": "Result", "parameters": ["type": "object"]]]
            ])
        }
        let result = try await instance.doGenerate(options: .init(prompt: prompt, responseFormat: .json(schema: ["type": "object"], name: "unused", description: "Result"), tools: [tool]))
        #expect(result.content.prefix(2) == [.reasoning(.init(text: "thinking")), .text(.init(text: #"{"value":42}"#))])
        #expect(result.finishReason.unified == (applicationCall ? .toolCalls : .stop))
        #expect(result.finishReason.raw == "tool_calls")
        if applicationCall { #expect(result.content.last == .toolCall(.init(toolCallId: "app", toolName: "json", input: "{}"))) }
    }

    @Test("JSON tool selection respects named choices and forces output when tools were disabled", arguments: [false, true])
    func jsonToolChoice(named: Bool) async throws {
        let instance = model { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            guard case .object(let payload) = body else { Issue.record("Missing request body"); return }
            #expect(payload["tool_choice"] == ["type": "function", "function": ["name": .string(named ? "json" : "json_1")]])
        }
        let result = try await instance.doGenerate(options: .init(prompt: prompt, responseFormat: .json(schema: ["type": "object"], name: nil, description: nil), tools: [tool], toolChoice: named ? .tool(toolName: "json") : LanguageModelV4ToolChoice.none))
        #expect(result.content.isEmpty)
    }

    @Test("JSON response tool streams become text while reasoning and usage survive")
    func jsonToolStream() async throws {
        let events = [
            #"{"choices":[{"index":0,"delta":{"reasoning":"think","content":"ignored"}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"answer","type":"function","function":{"name":"json_1","arguments":"{\"value\":"}}]}}]}"#,
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"42}"}}]},"finish_reason":"tool_calls"}],"x_groq":{"usage":{"prompt_tokens":20,"completion_tokens":3,"prompt_tokens_details":{"cached_tokens":0},"completion_tokens_details":{"reasoning_tokens":5}}}}"#
        ]
        let result = try await model(events: events).doStream(options: .init(prompt: prompt, responseFormat: .json(schema: ["type": "object"], name: nil, description: nil), tools: [tool], includeRawChunks: true))
        let parts = try await collect(result.stream)
        #expect(parts.compactMap { if case .textDelta(_, let text, _) = $0 { text } else { nil } }.joined() == #"{"value":42}"#)
        #expect(parts.contains(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)))
        #expect(parts.contains(.textStart(id: "answer", providerMetadata: nil)))
        #expect(parts.contains(.textEnd(id: "answer", providerMetadata: nil)))
        #expect(parts.filter { if case .raw = $0 { true } else { false } }.count == events.count)
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.inputTokens.cacheRead == 0)
        #expect(usage.outputTokens.text == 0)
        #expect(usage.outputTokens.reasoning == 5)
    }

    @Test("stream errors expose provider retry metadata", arguments: ["rate_limit_error", "authentication_error", "unknown"])
    func streamErrors(type: String) async throws {
        let event = try JSONEncoder().encode(JSONValue.object(["error": ["message": "failure", "type": .string(type), "extra": true]]))
        let result = try await model(events: [String(decoding: event, as: UTF8.self)]).doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)
        let payloads = parts.compactMap { part -> ProviderStreamError? in if case .error(.providerStreamError(let error)) = part { error } else { nil } }
        let error = try #require(payloads.first)
        #expect(error.message == "failure")
        #expect(error.type == type)
        #expect(error.statusCode == (type == "rate_limit_error" ? 429 : type == "authentication_error" ? 401 : nil))
        #expect(error.isRetryable == (type == "rate_limit_error" ? true : type == "authentication_error" ? false : nil))
        #expect(error.data == ["error": ["message": "failure", "type": .string(type)]])
    }

    @Test("none reasoning is supported only by Qwen and explicit options take precedence", arguments: ["qwen/qwen3.6-27b", "openai/gpt-oss-20b"])
    func reasoningNone(identifier: String) async throws {
        let instance = model(id: .init(rawValue: identifier)) { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            guard case .object(let payload) = body else { Issue.record("Missing request body"); return }
            #expect(payload["reasoning_effort"] == (identifier == "qwen/qwen3.6-27b" ? .string("none") : nil))
        }
        let result = try await instance.doGenerate(options: .init(prompt: prompt, reasoning: LanguageModelV4ReasoningEffort.none))
        #expect(result.content == [.text(.init(text: "ok"))])
        #expect(result.warnings.count == (identifier == "qwen/qwen3.6-27b" ? 0 : 1))
    }

    @Test("explicit null options and invalid response choices are refused")
    func validation() async throws {
        let instance = model()
        await #expect(throws: InvalidArgumentError.self) { try await instance.doGenerate(options: .init(prompt: prompt, providerOptions: ["groq": ["reasoningEffort": .null]])) }
        await #expect(throws: InvalidArgumentError.self) { try await instance.doGenerate(options: .init(prompt: prompt, providerOptions: ["groq": ["reasoningEffort": "unsupported"]])) }
        await #expect(throws: InvalidResponseDataError.self) { try await model(response: #"{"choices":[]}"#).doGenerate(options: .init(prompt: prompt)) }
    }

    @Test("numeric usage preserves success and projects each field independently", arguments: [false, true])
    func numericUsage(huge: Bool) async throws {
        let value = huge ? 1e100 : 1.5
        let read = huge ? 1e100 : 0.5
        let usage: JSONValue = ["prompt_tokens": .number(value), "completion_tokens": 1.5, "total_tokens": 4,
                                "prompt_tokens_details": ["cached_tokens": .number(read)], "completion_tokens_details": ["reasoning_tokens": 0.5]]
        let response: JSONValue = ["choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]], "usage": usage]
        let result = try await model(response: String(decoding: JSONEncoder().encode(response), as: UTF8.self)).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.text(.init(text: "ok"))])
        #expect(result.usage.inputTokens.total == nil)
        #expect(result.usage.inputTokens.cacheRead == nil)
        #expect(result.usage.inputTokens.noCache == (huge ? 0 : 1))
        #expect(result.usage.outputTokens.total == nil)
        #expect(result.usage.outputTokens.reasoning == nil)
        #expect(result.usage.outputTokens.text == 1)
        #expect(result.usage.raw == usage)
    }

    private func collect(_ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>) async throws -> [LanguageModelV4StreamPart] {
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in stream { parts.append(part) }
        return parts
    }
}
