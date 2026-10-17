import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import MistralProvider

@Suite("Mistral Conversations API")
struct MistralConversationModelTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Who won?"))], providerOptions: nil)]

    private func model(
        modelId: MistralConversationModelId = .mistralSmallLatest,
        response: String = #"{"conversation_id":"conversation-1","outputs":[],"usage":{}}"#,
        events: [String]? = nil,
        recorder: RequestRecorder? = nil,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> MistralConversationLanguageModel {
        createMistral(settings: .init(
            baseURL: "https://custom.example/v2/", apiKey: "key", headers: ["X-Provider": "provider"],
            fetch: { request in
                if let recorder { await recorder.record(request) }
                try inspect(request)
                let body: ProviderHTTPResponseBody
                if let events {
                    body = .stream(AsyncThrowingStream { continuation in
                        for event in events { continuation.yield(Data("data: \(event)\n\n".utf8)) }
                        continuation.finish()
                    })
                } else { body = .data(Data(response.utf8)) }
                return FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": events == nil ? "application/json" : "text/event-stream", "X-Response": "response"])!)
            }, generateId: { "source-id" }
        )).conversation(modelId: modelId)
    }

    private func search(_ premium: Bool = false, name: String = "search") throws -> LanguageModelV4Tool {
        let tool = premium ? mistral.tools.webSearchPremium() : mistral.tools.webSearch()
        return .provider(.init(id: try #require(tool.id), name: name, args: tool.args ?? [:]))
    }

    private func collect(_ result: LanguageModelV4StreamResult) async throws -> [LanguageModelV4StreamPart] {
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        return parts
    }

    @Test("built-in executions map tools, results, sources, and replay on the public API")
    func executionAndReplay() async throws {
        let payload = #"{"conversation_id":"conversation-1","outputs":[{"type":"tool.execution","id":"search-1","name":"web_search","arguments":"{\"url\":\"https://example.com\"}","function":"web_fetch","info":{"result":"Retrieved page"}},{"type":"message.output","model":"response-model","content":[{"type":"text","text":"Spain won."},{"type":"tool_reference","title":"Results","url":"https://example.com/results"}]},{"type":"message.output","content":[{"type":"thinking","thinking":[{"type":"text","text":"Think"}]},{"type":"tool_reference","url":"https://example.com/results"},{"type":"tool_reference","url":null}]}],"usage":{}}"#
        let recorder = RequestRecorder()
        let instance = model(response: payload, recorder: recorder)
        let first = try await instance.doGenerate(options: .init(prompt: prompt, tools: [search()]))
        #expect(first.content == [
            .toolCall(.init(toolCallId: "search-1", toolName: "search", input: #"{"arguments":"{\"url\":\"https://example.com\"}"}"#, providerExecuted: true, providerMetadata: ["mistral": ["type": "tool.execution", "name": "web_search", "function": "web_fetch"]])),
            .toolResult(.init(toolCallId: "search-1", toolName: "search", result: ["info": ["result": "Retrieved page"]])),
            .text(.init(text: "Spain won.")),
            .source(.url(id: "source-id", url: "https://example.com/results", title: "Results", providerMetadata: nil)),
            .reasoning(.init(text: "Think"))
        ])
        #expect(first.finishReason.unified == .stop)
        #expect(first.usage.inputTokens.total == 0)
        #expect(first.usage.outputTokens.total == 0)
        #expect(first.usage.raw == ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0])
        #expect(first.response?.id == "conversation-1")
        #expect(first.response?.modelId == "response-model")
        #expect(first.response?.headers?["x-response"] == "response")
        let history: LanguageModelV4Prompt = prompt + [
            .assistant(content: [
                .text(.init(text: "Before")), .reasoning(.init(text: "Think")),
                .toolCall(.init(toolCallId: "search-1", toolName: "search", input: ["arguments": #"{"url":"https://example.com"}"#], providerExecuted: true, providerOptions: ["mistral": ["function": .null, "name": "web_fetch"]])),
                .toolResult(.init(toolCallId: "search-1", toolName: "search", output: .json(value: ["info": ["result": "Retrieved page"]]))),
                .text(.init(text: "After")),
                .toolCall(.init(toolCallId: "function-1", toolName: "weather", input: ["city": "Madrid"]))
            ], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "function-1", toolName: "weather", output: .text(value: "Sunny")))], providerOptions: nil)
        ]
        let second = try await instance.doGenerate(options: .init(prompt: history))
        #expect(second.content == first.content.map { part in
            switch part {
            case .toolCall(let call): return .toolCall(.init(toolCallId: call.toolCallId, toolName: "web_search", input: call.input, providerExecuted: true, providerMetadata: call.providerMetadata))
            case .toolResult(let result): return .toolResult(.init(toolCallId: result.toolCallId, toolName: "web_search", result: result.result))
            default: return part
            }
        })
        let calls = await recorder.all()
        let firstBody = try JSONDecoder().decode(JSONValue.self, from: #require(calls.first?.httpBody))
        #expect(firstBody == ["model": "mistral-small-latest", "store": false, "inputs": [["type": "message.input", "role": "user", "content": [["type": "text", "text": "Who won?"]]]], "tools": [["type": "web_search"]], "completion_args": [:]])
        let replay = try decodeJSONBody(calls[1])
        let inputs = try jsonValue(from: #require(replay["inputs"]))
        #expect(inputs == .array([
            ["type": "message.input", "role": "user", "content": [["type": "text", "text": "Who won?"]]],
            ["type": "message.input", "role": "assistant", "content": [["type": "text", "text": "Before"], ["type": "thinking", "thinking": [["type": "text", "text": "Think"]], "closed": true]]],
            ["type": "function.call", "tool_call_id": "search-1", "name": "web_fetch", "arguments": #"{"url":"https://example.com"}"#],
            ["type": "function.result", "tool_call_id": "search-1", "result": "Retrieved page"],
            ["type": "message.input", "role": "assistant", "content": [["type": "text", "text": "After"]]],
            ["type": "function.call", "tool_call_id": "function-1", "name": "weather", "arguments": #"{"city":"Madrid"}"#],
            ["type": "function.result", "tool_call_id": "function-1", "result": "Sunny"]
        ]))
    }

    @Test("conversation request locations, forced premium tools, whitelist reasoning, and unsupported warnings", arguments: ["mistral-small-latest", "future-model"])
    func requestOptions(identifier: String) async throws {
        let recorder = RequestRecorder()
        let instance = model(modelId: .init(rawValue: identifier), recorder: recorder) { request in
            #expect(request.url?.absoluteString == "https://custom.example/v2/conversations")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
            #expect(request.value(forHTTPHeaderField: "X-Call") == "call")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-mistral/") == true)
        }
        let result = try await instance.doGenerate(options: .init(
            prompt: [.system(content: "Accurate", providerOptions: nil), .system(content: "Concise", providerOptions: nil)] + prompt,
            maxOutputTokens: 100, temperature: 0.3, stopSequences: ["END"], topP: 0.9, topK: 1,
            presencePenalty: 0.2, frequencyPenalty: 0.1, responseFormat: .json(schema: ["type": "object"], name: "answer", description: "result"),
            seed: 2, tools: [search(), search(true, name: "news"), .provider(.init(id: "mistral.unknown", name: "unknown", args: [:]))],
            toolChoice: .tool(toolName: "news"), headers: ["X-Call": "call"], reasoning: .high,
            providerOptions: ["mistral": ["safePrompt": true, "documentImageLimit": 1, "documentPageLimit": 2, "promptCacheKey": "cache", "parallelToolCalls": false, "strictJsonSchema": true]]
        ))
        let request = try #require(await recorder.first())
        let actual = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        var completion: JSONObject = ["max_tokens": 100, "temperature": 0.3, "top_p": 0.9, "presence_penalty": 0.2, "frequency_penalty": 0.1, "stop": ["END"], "random_seed": 2, "tool_choice": "any", "response_format": ["type": "json_schema", "json_schema": ["schema": ["type": "object"], "name": "answer", "description": "result", "strict": true]]]
        if identifier == "mistral-small-latest" { completion["reasoning_effort"] = "high" }
        #expect(actual == ["model": .string(identifier), "store": false, "instructions": "Accurate\n\nConcise", "inputs": [["type": "message.input", "role": "user", "content": [["type": "text", "text": "Who won?"]]]], "tools": [["type": "web_search_premium"]], "completion_args": .object(completion)])
        var expected: [SharedV4Warning] = [.unsupported(feature: "topK", details: nil)]
        if identifier == "future-model" { expected.append(.unsupported(feature: "reasoning", details: "This model does not support reasoning configuration.")) }
        for feature in ["safePrompt", "documentImageLimit", "documentPageLimit", "promptCacheKey", "parallelToolCalls"] {
            expected.append(.unsupported(feature: feature, details: "Not supported by the Mistral Conversations API."))
        }
        expected.append(.unsupported(feature: "provider-defined tool mistral.unknown", details: nil))
        #expect(result.warnings == expected)
    }

    @Test("function calls accept object or string arguments and expose tool-calls finish")
    func functionCalls() async throws {
        let payload = #"{"conversation_id":"functions","outputs":[{"type":"function.call","tool_call_id":"a","name":"weather","arguments":{"city":"Madrid"}},{"type":"function.call","tool_call_id":"b","name":"weather","arguments":"{\"city\":\"Paris\"}"}]}"#
        let result = try await model(response: payload).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.toolCall(.init(toolCallId: "a", toolName: "weather", input: #"{"city":"Madrid"}"#)), .toolCall(.init(toolCallId: "b", toolName: "weather", input: #"{"city":"Paris"}"#))])
        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.usage.inputTokens.total == nil)
    }

    @Test("streaming executions preserve ordered reasoning, text, source dedup, usage and raw events")
    func streamingExecution() async throws {
        let events = [
            #"{"type":"conversation.response.started","conversation_id":"conversation-1","created_at":"2026-01-01T00:00:00Z"}"#,
            #"{"type":"tool.execution.started","id":"search-1","name":"web_search_premium","arguments":"","function":"web_search"}"#,
            #"{"type":"tool.execution.delta","id":"search-1","name":"web_search_premium","arguments":"latest "}"#,
            #"{"type":"tool.execution.delta","id":"search-1","name":"web_search_premium","arguments":"results"}"#,
            #"{"type":"tool.execution.done","id":"search-1","name":"web_search_premium","function":"web_fetch","info":{"result":"context"}}"#,
            #"{"type":"message.output.delta","id":"message","model":"response-model","content":{"type":"thinking","thinking":[{"type":"text","text":"Think"}]}}"#,
            #"{"type":"message.output.delta","id":"message","content_index":1,"content":"Spain "}"#,
            #"{"type":"message.output.delta","id":"message","content_index":1,"content":{"type":"text","text":"won."}}"#,
            #"{"type":"message.output.delta","id":"message","content":{"type":"tool_reference","url":"https://example.com/results"}}"#,
            #"{"type":"message.output.delta","id":"other-message","content":{"type":"tool_reference","title":"duplicate","url":"https://example.com/results"}}"#,
            #"{"type":"conversation.response.done","usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30,"num_cached_tokens":2,"connector_tokens":5}}"#
        ]
        let result = try await model(events: events) { request in
            let body = try decodeJSONBody(request)
            #expect(body["stream"] as? Bool == true)
        }.doStream(options: .init(prompt: prompt, tools: [search(true, name: "news")], includeRawChunks: true))
        let parts = try await collect(result)
        let raw = parts.compactMap { part -> JSONValue? in if case .raw(let raw) = part { return raw }; return nil }
        #expect(raw == events.map { try! JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) })
        let withoutRaw = parts.filter { if case .raw = $0 { return false }; return true }
        #expect(Array(withoutRaw.dropLast()) == [
            .streamStart(warnings: []),
            .responseMetadata(id: "conversation-1", modelId: nil, timestamp: Date(timeIntervalSince1970: 1_767_225_600)),
            .toolInputStart(id: "search-1", toolName: "news", providerMetadata: nil, providerExecuted: true, dynamic: nil, title: nil),
            .toolInputDelta(id: "search-1", delta: #"{"arguments":"latest results"}"#, providerMetadata: nil),
            .toolInputEnd(id: "search-1", providerMetadata: nil),
            .toolCall(.init(toolCallId: "search-1", toolName: "news", input: #"{"arguments":"latest results"}"#, providerExecuted: true, providerMetadata: ["mistral": ["type": "tool.execution", "name": "web_search_premium", "function": "web_fetch"]])),
            .toolResult(.init(toolCallId: "search-1", toolName: "news", result: ["info": ["result": "context"]])),
            .responseMetadata(id: nil, modelId: "response-model", timestamp: nil),
            .reasoningStart(id: "message-0", providerMetadata: nil), .reasoningDelta(id: "message-0", delta: "Think", providerMetadata: nil),
            .reasoningEnd(id: "message-0", providerMetadata: nil), .textStart(id: "message-1", providerMetadata: nil),
            .textDelta(id: "message-1", delta: "Spain ", providerMetadata: nil), .textDelta(id: "message-1", delta: "won.", providerMetadata: nil),
            .source(.url(id: "source-id", url: "https://example.com/results", title: "https://example.com/results", providerMetadata: nil)),
            .textEnd(id: "message-1", providerMetadata: nil)
        ])
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.inputTokens.noCache == 8)
        #expect(usage.outputTokens.total == 20)
        guard case .object(let native) = usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(native["connector_tokens"] == 5)
    }

    @Test("incremental function-call stream emits the completed arguments and tool-calls finish")
    func streamingFunction() async throws {
        let events = [
            #"{"type":"function.call.delta","tool_call_id":"function-1","name":"weather","arguments":"{\"city\":","output_index":0}"#,
            #"{"type":"function.call.delta","tool_call_id":"function-1","name":"weather","arguments":"\"Madrid\"}","output_index":0}"#,
            #"{"type":"conversation.response.done","usage":{}}"#
        ]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt, tools: [search()])))
        #expect(parts.compactMap { if case .toolInputDelta(_, let delta, _) = $0 { return delta }; return nil }.joined() == #"{"city":"Madrid"}"#)
        #expect(parts.contains(.toolCall(.init(toolCallId: "function-1", toolName: "weather", input: #"{"city":"Madrid"}"#))))
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .toolCalls)
    }

    @Test("failed and incomplete conversations finish with error", arguments: [
        [#"{"type":"conversation.response.error","message":"Search failed","code":500}"#, #"{"type":"conversation.response.done"}"#],
        [#"{"type":"message.output.delta","id":"message","content":42}"#, #"{"type":"conversation.response.done"}"#],
        [#"{"type":"tool.execution.started","id":"search-1","name":"web_search","arguments":""}"#, #"{"type":"conversation.response.done","usage":{}}"#],
        [#"{"type":"message.output.delta","id":"message","content":"Truncated"}"#],
        [#"{"type":"tool.execution.done","id":"missing","name":"web_search"}"#, #"{"type":"conversation.response.done"}"#],
        [#"{"type":"conversation.response.done","usage":{"prompt_tokens":null}}"#]
    ])
    func incompleteStream(events: [String]) async throws {
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .error)
        if events.first?.contains("conversation.response.error") == true {
            #expect(parts.contains(.error(error: .value(["type": "conversation.response.error", "message": "Search failed", "code": 500]))))
        }
    }

    @Test("malformed response usage and output fields reject with API validation errors", arguments: [
        #"{"conversation_id":"c","outputs":[],"usage":{"prompt_tokens":null}}"#,
        #"{"conversation_id":"c","outputs":[{"type":"function.call","tool_call_id":"f","name":"weather","arguments":[] }]}"#,
        #"{"conversation_id":"c","outputs":[{"type":"message.output","content":[{"type":"thinking","thinking":[{"type":"wrong","text":"a"}]}]}]}"#
    ])
    func responseValidation(payload: String) async throws {
        do {
            _ = try await model(response: payload).doGenerate(options: .init(prompt: prompt))
            Issue.record("Expected API validation failure")
        } catch let error as APICallError {
            #expect(error.message == "Invalid JSON response")
            #expect(error.statusCode == 200)
        }
    }
}
