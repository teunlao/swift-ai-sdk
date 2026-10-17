import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenResponsesProvider

@Suite("Open Responses public model")
struct OpenResponsesLanguageModelTests {
    @Test("captured generation preserves reasoning boundaries, item metadata and usage")
    func capturedGeneration() async throws {
        let fields = try JSONDecoder().decode(JSONObject.self, from: openResponsesFixture("lmstudio-basic.json"))
        let endpoint = OpenResponsesTestEndpoint(fields)
        let provider = try openResponsesProvider(endpoint)
        let result = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt))
        #expect(result.content == [
            .reasoning(.init(text: "reasoning content", providerMetadata: ["acme": ["itemId": "rs_3l1z5wpifxkwxhj459ya7", "reasoningSummary": [], "reasoningContent": [["type": "reasoning_text", "text": "reasoning content"]]]])),
            .text(.init(text: "text content", providerMetadata: ["acme": ["itemId": "msg_p1y190hl7hj1xyfqr1cir"]]))
        ])
        #expect(result.usage.inputTokens.total == 136)
        #expect(result.usage.inputTokens.noCache == 136)
        #expect(result.usage.outputTokens.total == 3677)
        #expect(result.usage.outputTokens.text == 1221)
        #expect(result.usage.outputTokens.reasoning == 2456)
        #expect(result.usage.raw == fields["usage"])
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 1_768_900_049))
        #expect(result.response?.headers?["x-response"] == "response-value")
        #expect(result.finishReason == .init(unified: .stop))
        #expect(try await endpoint.lastBody() == ["model": "model", "input": [["type": "message", "role": "user", "content": [["type": "input_text", "text": "Hello"]]]]])
    }

    @Test("request settings and reasoning use provider-native names and precedence", arguments: [false, true])
    func requestSettings(structured: Bool) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, structuredOutputs: structured))
        let result = try await provider("model").doGenerate(options: .init(
            prompt: openResponsesTestPrompt, maxOutputTokens: 100, temperature: 0.5, stopSequences: ["END"], topP: 0.9, topK: 1,
            presencePenalty: 0.1, frequencyPenalty: 0.2, responseFormat: .json(schema: ["type": "object"], name: "answer", description: "description"), seed: 1,
            reasoning: .high, providerOptions: ["acme": ["reasoningEffort": "endpoint-level", "reasoningSummary": "auto"]]))
        let body = try await endpoint.lastBody()
        #expect(body["max_output_tokens"] == 100)
        #expect(body["temperature"] == 0.5)
        #expect(body["top_p"] == 0.9)
        #expect(body["presence_penalty"] == 0.1)
        #expect(body["frequency_penalty"] == 0.2)
        #expect(body["reasoning"] == ["effort": "endpoint-level", "summary": "auto"])
        if structured { #expect(body["text"] == ["format": ["type": "json_schema", "name": "answer", "description": "description", "schema": ["type": "object"], "strict": true]]) }
        else { #expect(body["text"] == nil) }
        var warnings: [SharedV4Warning] = [.unsupported(feature: "stopSequences", details: nil), .unsupported(feature: "topK", details: nil), .unsupported(feature: "seed", details: nil)]
        if !structured { warnings.append(.unsupported(feature: "responseFormat", details: nil)) }
        #expect(result.warnings == warnings)
    }

    @Test("nullish reasoning options fall back to top-level effort and schema-less JSON uses json_object")
    func nullishReasoning() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        let result = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt, responseFormat: .json(schema: nil, name: nil, description: nil), reasoning: .minimal, providerOptions: ["acme": ["reasoningEffort": .null, "reasoningSummary": .null]]))
        let body = try await endpoint.lastBody()
        #expect(body["reasoning"] == ["effort": "low"])
        #expect(body["text"] == ["format": ["type": "json_object"]])
        #expect(result.warnings == [.compatibility(feature: "reasoning", details: "reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\".")])
    }

    @Test("function tools and named or aggregate choices use the endpoint schema", arguments: ["auto", "none", "required", "named"])
    func functionRequest(choice: String) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        let selected: LanguageModelV4ToolChoice
        switch choice {
        case "auto": selected = .auto
        case "none": selected = .none
        case "required": selected = .required
        default: selected = .tool(toolName: "lookup")
        }
        _ = try await provider("model").doGenerate(options: .init(prompt: [], tools: [.function(.init(name: "lookup", inputSchema: ["type": "object"], description: "Lookup", strict: true))], toolChoice: selected))
        let body = try await endpoint.lastBody()
        #expect(body["tools"] == [["type": "function", "name": "lookup", "description": "Lookup", "parameters": ["type": "object"], "strict": true]])
        #expect(body["tool_choice"] == (choice == "named" ? ["type": "function", "name": "lookup"] : .string(choice)))
    }

    @Test("custom string tools retain grammar, choice, final input and replay metadata")
    func customTool() async throws {
        let output: JSONValue = ["type": "custom_tool_call", "id": "custom-item", "call_id": "call", "name": "code", "input": "print(1)", "status": "completed"]
        let endpoint = OpenResponsesTestEndpoint(openResponsesTestResponse(output: [output]))
        let provider = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", fetch: { request in try await endpoint.fetch(request) }, customToolId: "acme.raw"))
        let custom = provider.tools.customTool(.init(description: "Run", format: .grammar(syntax: .lark, definition: "start: /.+/")))
        let tool = LanguageModelV4Tool.provider(.init(id: try #require(custom.id), name: "code", args: custom.args ?? [:]))
        let result = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt, tools: [tool], toolChoice: .tool(toolName: "code")))
        let body = try await endpoint.lastBody()
        #expect(body["tools"] == [["type": "custom", "name": "code", "description": "Run", "format": ["type": "grammar", "syntax": "lark", "definition": "start: /.+/"]]])
        #expect(body["tool_choice"] == ["type": "custom", "name": "code"])
        #expect(result.content == [.toolCall(.init(toolCallId: "call", toolName: "code", input: #""print(1)""#, providerMetadata: ["acme": ["itemId": "custom-item"]]))])
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(#""print(1)""#.utf8))
        let validated = try await validateTypes(ValidateTypesOptions(value: input, schema: custom.inputSchema))
        #expect(validated == .string("print(1)"))
        _ = try await provider("model").doGenerate(options: .init(prompt: [.assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "code", input: input, providerOptions: ["acme": ["itemId": "custom-item"]]))], providerOptions: nil), .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "code", output: .text(value: "done")))], providerOptions: nil)], tools: [tool]))
        let replay = try await endpoint.lastBody()
        #expect(replay["input"] == [["type": "custom_tool_call", "id": "custom-item", "call_id": "call", "name": "code", "input": "print(1)"], ["type": "custom_tool_call_output", "call_id": "call", "output": "done"]])
    }

    @Test("captured reasoning-summary streams do not repeat done text and retain replay metadata")
    func capturedReasoningStream() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let lines = String(decoding: try openResponsesFixture("reasoning-summary.chunks.txt"), as: UTF8.self).split(separator: "\n").map(String.init)
        await endpoint.setLines(lines)
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: openResponsesTestPrompt)))
        #expect(Array(parts.dropLast()) == [
            .streamStart(warnings: []), .reasoningStart(id: "rs_1", providerMetadata: nil),
            .reasoningDelta(id: "rs_1", delta: "Think", providerMetadata: nil), .reasoningDelta(id: "rs_1", delta: "ing.", providerMetadata: nil),
            .reasoningEnd(id: "rs_1", providerMetadata: ["acme": ["itemId": "rs_1", "reasoningSummary": [["type": "summary_text", "text": "Thinking."]], "reasoningContent": .null]])
        ])
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.inputTokens.total == 1)
        #expect(usage.outputTokens.text == 1)
    }

    @Test("completed function arguments take precedence over partial argument events")
    func functionStream() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let events: [JSONValue] = [
            ["type": "response.output_item.added", "item": ["type": "function_call", "id": "function", "call_id": "call", "name": "lookup", "arguments": ""]],
            ["type": "response.function_call_arguments.delta", "item_id": "function", "delta": "{"],
            ["type": "response.function_call_arguments.done", "item_id": "function", "arguments": #"{"buffered":true}"#],
            ["type": "response.output_item.done", "item": ["type": "function_call", "id": "function", "call_id": "call", "name": "lookup", "arguments": #"{"final":true}"#]],
            ["type": "response.completed", "response": ["usage": ["input_tokens": 10, "output_tokens": 4, "input_tokens_details": ["cached_tokens": 2, "cache_write_tokens": 3], "output_tokens_details": ["reasoning_tokens": 6]]]]
        ]
        try await endpoint.setEvents(events)
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: openResponsesTestPrompt)))
        #expect(Array(parts.dropFirst().dropLast()) == [.toolCall(.init(toolCallId: "call", toolName: "lookup", input: #"{"final":true}"#, providerMetadata: ["acme": ["itemId": "function"]]))])
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .toolCalls)
        #expect(usage.inputTokens.noCache == 5)
        #expect(usage.inputTokens.cacheWrite == 3)
        #expect(usage.outputTokens.text == -2)
    }

    @Test("custom tool streams accumulate raw text but expose a JSON string final input")
    func customStream() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        try await endpoint.setEvents([
            ["type": "response.output_item.added", "item": ["type": "custom_tool_call", "id": "custom", "call_id": "call", "name": "code", "input": ""]],
            ["type": "response.custom_tool_call_input.delta", "item_id": "custom", "delta": "print("],
            ["type": "response.custom_tool_call_input.done", "item_id": "custom", "input": "print(1)"],
            ["type": "response.output_item.done", "item": ["type": "custom_tool_call", "id": "custom", "call_id": "call", "name": "code", "input": ""]],
            ["type": "response.completed", "response": [:]]
        ])
        let parts = try await openResponsesCollect(openResponsesProvider(endpoint)("model").doStream(options: .init(prompt: openResponsesTestPrompt)))
        #expect(Array(parts.dropFirst().dropLast()) == [
            .toolInputStart(id: "call", toolName: "code", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "call", delta: "print(", providerMetadata: nil), .toolInputEnd(id: "call", providerMetadata: nil),
            .toolCall(.init(toolCallId: "call", toolName: "code", input: #""print(1)""#, providerMetadata: ["acme": ["itemId": "custom"]]))
        ])
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .toolCalls)
    }

    @Test("text streaming ignores redundant done text and preserves citation metadata at item end")
    func textStream() async throws {
        let citation: JSONValue = ["type": "url_citation", "start_index": 0, "end_index": 5, "url": "https://example.com", "title": "Source"]
        let endpoint = OpenResponsesTestEndpoint()
        try await endpoint.setEvents([
            ["type": "response.output_item.added", "item": ["type": "message", "id": "message", "content": []]],
            ["type": "response.output_text.delta", "item_id": "message", "delta": "Hel"],
            ["type": "response.output_text.delta", "item_id": "message", "delta": "lo"],
            ["type": "response.output_text.done", "item_id": "message", "text": "Hello"],
            ["type": "response.output_item.done", "item": ["type": "message", "id": "message", "content": [["type": "output_text", "text": "Hello", "annotations": .array([citation])]]]],
            ["type": "response.completed", "response": [:]]
        ])
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        #expect(Array(parts.dropFirst().dropLast()) == [.textStart(id: "message", providerMetadata: nil), .textDelta(id: "message", delta: "Hel", providerMetadata: nil), .textDelta(id: "message", delta: "lo", providerMetadata: nil), .textEnd(id: "message", providerMetadata: ["acme": ["itemId": "message", "annotations": .array([citation])]])])
    }

    @Test("unfinished reasoning closes its original ID and malformed JSON remains a typed error")
    func unfinishedReasoning() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        await endpoint.setLines([#"{"type":"response.output_item.added","item":{"type":"reasoning","id":"original","summary":[]}}"#, "{invalid}"])
        let provider = try openResponsesProvider(endpoint)
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: openResponsesTestPrompt)))
        #expect(parts.contains(.reasoningEnd(id: "original", providerMetadata: nil)))
        let errors = parts.compactMap { part -> (any Error)? in if case .error(.error(let error)) = part { return error }; return nil }
        #expect(errors.first is JSONParseError)
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .other)
        #expect(usage.inputTokens.noCache == nil)
    }
}
