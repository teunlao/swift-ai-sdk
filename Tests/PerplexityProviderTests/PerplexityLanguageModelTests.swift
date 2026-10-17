import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import PerplexityProvider

@Suite("Perplexity Agent API")
struct PerplexityLanguageModelTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
    private actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
        func last() -> URLRequest? { request }
    }

    private static func response(output: [JSONValue] = [], status: String = "completed", usage: JSONValue? = nil) -> JSONObject {
        var value: JSONObject = ["id": "response-1", "created_at": 1000, "model": "routed-model", "object": "response", "output": .array(output), "status": .string(status)]
        if let usage { value["usage"] = usage }
        return value
    }
    private func model(
        id: String = "low", response: JSONObject? = nil, events: [JSONValue]? = nil, status: Int = 200,
        capture: Capture? = nil, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> PerplexityLanguageModel {
        let payload = response ?? Self.response()
        return createPerplexity(settings: .init(apiKey: "key", headers: ["X-Provider": "provider"], fetch: { request in
            if let capture { await capture.store(request) }
            try inspect(request)
            let body: ProviderHTTPResponseBody
            if let events {
                let chunks = try events.map { Data("data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n".utf8) }
                body = .stream(AsyncThrowingStream { continuation in
                    for chunk in chunks { continuation.yield(chunk) }
                    continuation.finish()
                })
            } else { body = .data(try JSONEncoder().encode(payload)) }
            return FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": events == nil ? "application/json" : "text/event-stream", "X-Response": "response-header"])!)
        })).languageModel(.init(rawValue: id))
    }
    private func body(_ capture: Capture) async throws -> JSONObject {
        let request = try #require(await capture.last())
        return try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
    }
    private func collect(_ result: LanguageModelV4StreamResult) async throws -> [LanguageModelV4StreamPart] {
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        return parts
    }
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("captured Agent search responses preserve source IDs, usage, cost and raw metadata")
    func capturedGeneration() async throws {
        let payload = try JSONDecoder().decode(JSONObject.self, from: fixture("agent-web-search.json"))
        let result = try await model(response: payload).doGenerate(options: .init(prompt: prompt))
        #expect(result.content.count == 2)
        guard case .source(.url(let id, let url, _, let metadata)) = result.content[0] else { Issue.record("Missing source"); return }
        #expect(id == "7")
        #expect(url == "https://www.typescriptlang.org/")
        #expect(metadata?["perplexity"]?["resultId"] == 7)
        #expect(metadata?["perplexity"]?["date"] == .null)
        #expect(result.content[1] == .text(.init(text: "The official TypeScript website is **typescriptlang.org**; TypeScript is a strongly typed programming language that builds on JavaScript with syntax for types.[7]")))
        #expect(result.finishReason == .init(unified: .stop, raw: "completed"))
        #expect(result.usage.inputTokens.total == 3007)
        #expect(result.usage.inputTokens.noCache == 3)
        #expect(result.usage.inputTokens.cacheRead == 1780)
        #expect(result.usage.inputTokens.cacheWrite == 1224)
        #expect(result.usage.outputTokens.text == 36)
        #expect(result.usage.raw == payload["usage"])
        #expect(result.providerMetadata?["perplexity"]?["cost"] == ["inputTokensCost": 0, "outputTokensCost": 0.00002, "requestCost": .null, "totalCost": 0.00119, "currency": "USD", "cacheCreationCost": 0.00015, "cacheReadCost": 0.00002, "toolCallsCost": 0.001])
        #expect(result.providerMetadata?["perplexity"]?["usage"] == ["citationTokens": .null, "numSearchQueries": 1])
        #expect(result.response?.id == "resp_8762b9bb-2d06-44a4-b68c-412dc85b24db")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 1_790_374_547))
        let raw = try jsonValue(from: #require(result.response?.body))
        #expect(raw == .object(payload))
    }

    @Test("presets and direct models route through Agent input", arguments: ["fast", "low", "medium", "high", "xhigh", "custom-model"])
    func modelSelection(id: String) async throws {
        let capture = Capture()
        _ = try await model(id: id, capture: capture).doGenerate(options: .init(prompt: prompt))
        let actual = try await body(capture)
        let selection = id == "custom-model" ? "model" : "preset"
        #expect(actual == [selection: .string(id), "input": [["type": "message", "role": "user", "content": "Hello"]]])
    }

    @Test("Agent options, loose fields and function tools serialize at the API boundary")
    func requestOptions() async throws {
        let capture = Capture()
        let native: [JSONValue] = [
            ["type": "web_search", "max_results": 2, "filters": ["search_recency_filter": "month", "search_domain_filter": ["example.com"], "future": true], "user_location": ["latitude": 1.5, "country": "US"], "max_urls": "future field"],
            ["type": "fetch_url", "max_urls": 1.5], ["type": "people_search"], ["type": "finance_search"], ["type": "sandbox"],
            ["type": "mcp", "server_label": "remote", "server_url": "https://tools.example.com", "headers": ["X-Tool": "value"], "allowed_tools": ["lookup"], "defer_loading": true],
            ["type": "connector", "id": "connector-id", "server_label": "connector", "server_description": "description"]
        ]
        let options: JSONObject = ["instructions": "Agent instruction", "tools": .array(native), "models": ["fallback-model"], "max_steps": 4, "max_tool_calls": 0, "previous_response_id": "previous", "store": false, "language_preference": "en", "future_option": ["enabled": true], "max_output_tokens": 999, "temperature": 99]
        let result = try await model(capture: capture) { request in
            #expect(request.url?.absoluteString == "https://api.perplexity.ai/v1/agent")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
            #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-perplexity/") == true)
        }.doGenerate(options: .init(prompt: prompt, maxOutputTokens: 200, temperature: 0.4, topP: 0.9,
            responseFormat: .json(schema: ["type": "object"], name: "answer", description: "structured"),
            tools: [.function(.init(name: "weather", inputSchema: ["type": "object"], description: "Weather", strict: true))],
            headers: ["X-Request": "request"], reasoning: .high, providerOptions: ["perplexity": options]))
        let actual = try await body(capture)
        #expect(actual["preset"] == "low")
        #expect(actual["max_output_tokens"] == 200)
        #expect(actual["temperature"] == 0.4)
        #expect(actual["top_p"] == 0.9)
        #expect(actual["reasoning"] == ["effort": "high"])
        #expect(actual["future_option"] == ["enabled": true])
        #expect(actual["max_steps"] == 4)
        #expect(actual["max_tool_calls"] == 0)
        #expect(actual["previous_response_id"] == "previous")
        #expect(actual["store"] == false)
        #expect(actual["response_format"] == ["type": "json_schema", "json_schema": ["name": "answer", "description": "structured", "schema": ["type": "object"], "strict": true]])
        #expect(actual["tools"] == .array(native + [["type": "function", "name": "weather", "description": "Weather", "parameters": ["type": "object"], "strict": true]]))
        #expect(result.response?.headers?["x-response"] == "response-header")
    }

    @Test("unsupported settings, prompt reasoning and tool choices warn in source order")
    func warnings() async throws {
        let capture = Capture()
        let result = try await model(capture: capture).doGenerate(options: .init(
            prompt: prompt + [.assistant(content: [.reasoning(.init(text: "hidden"))], providerOptions: nil)],
            stopSequences: ["END"], topK: 1, presencePenalty: 0.1, frequencyPenalty: 0.2,
            responseFormat: .json(schema: nil, name: nil, description: nil), seed: 1,
            tools: [.provider(.init(id: "vendor.tool", name: "visible-name", args: [:]))], toolChoice: .required,
            reasoning: LanguageModelV4ReasoningEffort.none))
        #expect(result.warnings == [
            .unsupported(feature: "topK", details: nil), .unsupported(feature: "frequencyPenalty", details: nil),
            .unsupported(feature: "presencePenalty", details: nil), .unsupported(feature: "stopSequences", details: nil),
            .unsupported(feature: "seed", details: nil), .unsupported(feature: "reasoning content in prompt", details: nil),
            .unsupported(feature: "provider-defined tool visible-name", details: nil),
            .unsupported(feature: "toolChoice", details: "The Perplexity Agent API currently selects tools automatically."),
            .unsupported(feature: "reasoning \"none\"", details: nil), .unsupported(feature: "JSON response format without a schema", details: nil)
        ])
        let actual = try await body(capture)
        #expect(actual == ["preset": "low", "input": [["type": "message", "role": "user", "content": "Hello"]]])
    }

    @Test("max reasoning maps to xhigh and explicit provider reasoning wins", arguments: [false, true])
    func reasoningOverride(override: Bool) async throws {
        let capture = Capture()
        let options: SharedV4ProviderOptions? = override ? ["perplexity": ["reasoning": ["future": true]]] : nil
        let result = try await model(capture: capture).doGenerate(options: .init(prompt: prompt, reasoning: .max, providerOptions: options))
        let actual = try await body(capture)
        #expect(actual["reasoning"] == (override ? ["future": true] : ["effort": "xhigh"]))
        #expect(result.warnings == (override ? [] : [.compatibility(feature: "reasoning", details: "reasoning \"max\" is not directly supported by this model. mapped to effort \"xhigh\".")]))
    }

    @Test("known Agent option schemas reject nulls, unsafe counts and malformed native tools", arguments: [
        ["max_steps": JSONValue.number(0)], ["max_steps": .number(1.5)], ["max_tool_calls": .number(-1)], ["max_steps": .number(9_007_199_254_740_992)],
        ["instructions": .null], ["reasoning": ["effort": "none"]],
        ["tools": [["type": "web_search", "max_results": 0]]], ["tools": [["type": "web_search", "filters": ["search_recency_filter": "invalid"]]]],
        ["tools": [["type": "mcp", "server_label": "remote"]]], ["tools": [["type": "mcp", "server_label": "remote", "server_url": "url", "headers": ["bad": 1]]]],
        ["tools": [["type": "connector", "server_label": "connector"]]], ["tools": [["type": "unknown"]]],
        ["skills": [["type": "builtin", "name": "invalid"]]], ["skills": [["type": "inline", "name": "skill", "description": "description"]]]
    ])
    func invalidOptions(options: JSONObject) async throws {
        await #expect(throws: InvalidArgumentError.self) { _ = try await model().doGenerate(options: .init(prompt: prompt, providerOptions: ["perplexity": options])) }
    }

    @Test("images and thought-signed tool turns replay through Agent input")
    func replay() async throws {
        let capture = Capture()
        let history: LanguageModelV4Prompt = [
            .system(content: "System", providerOptions: nil),
            .user(content: [.text(.init(text: "Describe")), .file(.init(data: .base64("AAECAw=="), mediaType: "image/png")), .file(.init(data: .url(URL(string: "https://example.com/image.png")!), mediaType: "image/png"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "Working")), .toolCall(.init(toolCallId: "call", toolName: "tool", input: .null, providerOptions: ["perplexity": ["thoughtSignature": "signature"]])), .toolResult(.init(toolCallId: "inline", toolName: "tool", output: .content(value: [.text(text: "One", providerOptions: nil), .text(text: "Two", providerOptions: nil)]), providerOptions: ["perplexity": ["thoughtSignature": .null]]))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "tool", output: .json(value: ["result": true]), providerOptions: ["perplexity": ["thoughtSignature": "continued"]]))], providerOptions: nil)
        ]
        _ = try await model(capture: capture).doGenerate(options: .init(prompt: history))
        let actual = try await body(capture)
        #expect(actual["input"] == [
            ["type": "message", "role": "system", "content": "System"],
            ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Describe"], ["type": "input_image", "image_url": "data:image/png;base64,AAECAw=="], ["type": "input_image", "image_url": "https://example.com/image.png"]]],
            ["type": "message", "role": "assistant", "content": "Working"],
            ["type": "function_call", "call_id": "call", "name": "tool", "arguments": "{}", "thought_signature": "signature"],
            ["type": "function_call_output", "call_id": "inline", "name": "tool", "output": "OneTwo"],
            ["type": "function_call_output", "call_id": "call", "name": "tool", "output": #"{"result":true}"#, "thought_signature": "continued"]
        ])
    }

    @Test("unsupported input variants fail at the public model boundary", arguments: ["pdf", "reference", "text-image", "assistant-file", "approval", "custom-result"])
    func unsupportedInput(kind: String) async throws {
        let history: LanguageModelV4Prompt
        switch kind {
        case "pdf": history = [.user(content: [.file(.init(data: .base64("JVBERi0="), mediaType: "application/pdf"))], providerOptions: nil)]
        case "reference": history = [.user(content: [.file(.init(data: .reference(["perplexity": "file"]), mediaType: "image/png"))], providerOptions: nil)]
        case "text-image": history = [.user(content: [.file(.init(data: .text("image"), mediaType: "image/png"))], providerOptions: nil)]
        case "assistant-file": history = [.assistant(content: [.file(.init(data: .base64("AAECAw=="), mediaType: "image/png"))], providerOptions: nil)]
        case "approval": history = [.tool(content: [.toolApprovalResponse(.init(approvalId: "approval", approved: true))], providerOptions: nil)]
        default: history = [.tool(content: [.toolResult(.init(toolCallId: "call", toolName: "tool", output: .content(value: [.custom(providerOptions: nil)])))], providerOptions: nil)]
        }
        await #expect(throws: UnsupportedFunctionalityError.self) { _ = try await model().doGenerate(options: .init(prompt: history)) }
    }

    @Test("numeric search sources upgrade earlier annotations without changing content position")
    func sourceUpgrade() async throws {
        let output: [JSONValue] = [
            ["type": "message", "content": [["type": "output_text", "text": "Answer", "annotations": [["url": "https://example.com/source", "title": "Annotation"]]], ["type": "output_text", "text": "Tail"]]],
            ["type": "fetch_url_results", "contents": [["url": "https://example.com/source", "title": "Fetched"]]],
            ["type": "search_results", "results": [["id": 7, "url": "https://example.com/source", "title": "Search", "snippet": "Snippet"]]]
        ]
        let result = try await model(response: Self.response(output: output)).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.text(.init(text: "Answer")), .source(.url(id: "7", url: "https://example.com/source", title: "Search", providerMetadata: ["perplexity": ["resultId": 7, "snippet": "Snippet", "date": .null, "lastUpdated": .null, "source": .null]])), .text(.init(text: "Tail"))])
    }

    @Test("function calls preserve thought signatures and map requires-action finish")
    func functionCall() async throws {
        let output: [JSONValue] = [["type": "function_call", "id": "item", "call_id": "call", "name": "weather", "arguments": #"{"city":"Paris"}"#, "thought_signature": "signature"], ["type": "function_call", "call_id": "missing-name", "arguments": "{}"]]
        let result = try await model(response: Self.response(output: output, status: "requires_action")).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.toolCall(.init(toolCallId: "call", toolName: "weather", input: #"{"city":"Paris"}"#, providerMetadata: ["perplexity": ["itemId": "item", "thoughtSignature": "signature"]]))])
        #expect(result.finishReason == .init(unified: .toolCalls, raw: "requires_action"))
    }

    @Test("incomplete reasons override response status", arguments: ["max_output_tokens", "content_filter"])
    func incompleteGeneration(reason: String) async throws {
        var response = Self.response(status: "incomplete")
        response["incomplete_details"] = ["reason": .string(reason)]
        let result = try await model(response: response).doGenerate(options: .init(prompt: prompt))
        #expect(result.finishReason == .init(unified: reason == "max_output_tokens" ? .length : .contentFilter, raw: reason))
    }

    @Test("HTTP-success Agent failures become non-retryable API errors")
    func failedGeneration() async throws {
        var response = Self.response(status: "failed")
        response["error"] = ["message": "Agent run failed", "type": "server_error"]
        do {
            _ = try await model(response: response).doGenerate(options: .init(prompt: prompt))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Agent run failed")
            #expect(error.statusCode == 400)
            #expect(error.isRetryable == false)
            let raw = try JSONDecoder().decode(JSONObject.self, from: Data(#require(error.responseBody).utf8))
            #expect(raw == response)
        }
    }

    @Test("unhandled native traces remain raw and do not masquerade as search results")
    func nativeTrace() async throws {
        let finance: JSONValue = ["type": "finance_results", "results": [["category": "quote", "content": "AAPL", "sources": ["https://example.com/quote"]]]]
        let response = Self.response(output: [finance, ["type": "message", "content": [["type": "output_text", "text": "Answer"]]]])
        let generated = try await model(response: response).doGenerate(options: .init(prompt: prompt))
        #expect(generated.content == [.text(.init(text: "Answer"))])
        let raw = try jsonValue(from: #require(generated.response?.body))
        #expect(raw == .object(response))
        let trace: JSONValue = ["type": "response.output_item.done", "item": finance]
        let parts = try await collect(model(events: [trace, ["type": "response.completed", "response": .object(response)]]).doStream(options: .init(prompt: prompt, includeRawChunks: true)))
        #expect(parts.contains(.raw(rawValue: trace)))
        #expect(parts.contains(.textDelta(id: "1", delta: "Answer", providerMetadata: nil)))
        guard case .finish(let finish, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish.unified == .stop)
    }

    @Test("malformed handled output cannot fall back to unhandled", arguments: [
        JSONValue.object(["type": "message", "content": "invalid"]),
        ["type": "search_results", "results": [["title": "Missing URL"]]],
        ["type": "fetch_url_results", "contents": [["url": "https://example.com"]]],
        ["type": "function_call", "arguments": 3]
    ])
    func malformedOutput(item: JSONValue) async throws {
        await #expect(throws: APICallError.self) { _ = try await model(response: Self.response(output: [item])).doGenerate(options: .init(prompt: prompt)) }
    }

    @Test("captured web-search streams recover terminal text and deduplicate numeric sources")
    func capturedStream() async throws {
        let text = String(decoding: try fixture("agent-web-search.chunks.txt"), as: UTF8.self)
        let events = try text.split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let capture = Capture()
        let parts = try await collect(model(events: events, capture: capture).doStream(options: .init(prompt: prompt, includeRawChunks: true)))
        let actualText = parts.compactMap { part -> String? in if case .textDelta(_, let text, _) = part { return text }; return nil }.joined()
        #expect(actualText == "The official TypeScript website is **typescriptlang.org**; TypeScript is a strongly typed programming language that builds on JavaScript and adds syntax for types.[7]")
        let sources = parts.compactMap { part -> LanguageModelV4Source? in if case .source(let source) = part { return source }; return nil }
        #expect(sources.count == 1)
        guard case .url(let id, let url, _, _) = sources[0] else { Issue.record("Missing URL source"); return }
        #expect(id == "7")
        #expect(url == "https://www.typescriptlang.org/")
        #expect(parts.filter { if case .responseMetadata = $0 { return true }; return false }.count == 1)
        #expect(parts.contains(.responseMetadata(id: "resp_5619693e-4309-4fec-b395-5e21e59aba39", modelId: "fast", timestamp: Date(timeIntervalSince1970: 1_790_374_575))))
        guard case .finish(let finish, let usage, let metadata) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish == .init(unified: .stop, raw: "completed"))
        #expect(usage.inputTokens.noCache == 3)
        #expect(usage.outputTokens.text == 37)
        guard case .object(let cost) = metadata?["perplexity"]?["cost"] else { Issue.record("Missing cost"); return }
        #expect(cost["totalCost"] == 0.00105)
        let actual = try await body(capture)
        #expect(actual == ["preset": "low", "input": [["type": "message", "role": "user", "content": "Hello"]], "stream": true])
    }

    @Test("terminal events recover text even without deltas", arguments: ["response.output_text.done", "response.output_item.done", "response.completed"])
    func terminalText(type: String) async throws {
        let message: JSONValue = ["type": "message", "id": "msg", "content": [["type": "output_text", "text": "Answer"]]]
        let event: JSONValue = ["type": .string(type), "item_id": "msg", "output_index": 0, "text": "Answer", "item": message, "response": .object(Self.response(output: [message]))]
        let parts = try await collect(model(events: [event]).doStream(options: .init(prompt: prompt)))
        #expect(parts.filter { switch $0 { case .textStart, .textDelta, .textEnd: true; default: false } } == [.textStart(id: "msg", providerMetadata: nil), .textDelta(id: "msg", delta: "Answer", providerMetadata: nil), .textEnd(id: "msg", providerMetadata: nil)])
    }

    @Test("partial terminal output appends only missing suffixes and closes content once")
    func partialText() async throws {
        let message: JSONValue = ["type": "message", "id": "msg", "content": [["type": "output_text", "text": "Hello world."], ["type": "output_text", "text": "Second part."]]]
        let events: [JSONValue] = [
            ["type": "response.output_text.delta", "item_id": "msg", "content_index": 0, "delta": "Hello "],
            ["type": "response.output_text.done", "item_id": "msg", "content_index": 0, "text": "Hello world."],
            ["type": "response.output_text.delta", "item_id": "msg", "content_index": 1, "delta": "Second "],
            ["type": "response.output_item.done", "item": message, "output_index": 0],
            ["type": "response.output_text.delta", "item_id": "msg", "content_index": 0, "delta": "duplicate"],
            ["type": "response.completed", "response": .object(Self.response(output: [message]))]
        ]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        #expect(parts.filter { switch $0 { case .textStart, .textDelta, .textEnd: true; default: false } } == [
            .textStart(id: "msg", providerMetadata: nil), .textDelta(id: "msg", delta: "Hello ", providerMetadata: nil), .textDelta(id: "msg", delta: "world.", providerMetadata: nil), .textEnd(id: "msg", providerMetadata: nil),
            .textStart(id: "msg:1", providerMetadata: nil), .textDelta(id: "msg:1", delta: "Second ", providerMetadata: nil), .textDelta(id: "msg:1", delta: "part.", providerMetadata: nil), .textEnd(id: "msg:1", providerMetadata: nil)
        ])
    }

    @Test("sources upgrade across annotations and fetches and flush pending URLs in insertion order")
    func streamedSources() async throws {
        let message: JSONValue = ["type": "message", "content": [["type": "output_text", "text": "Answer", "annotations": [["url": "https://example.com/a", "title": "Annotation"], ["url": "https://example.com/b", "title": "Second"]]]]]
        let events: [JSONValue] = [
            ["type": "response.output_item.done", "item": message],
            ["type": "response.reasoning.fetch_url_results", "contents": [["url": "https://example.com/a", "title": "Fetched"], ["url": "https://example.com/c", "title": "Third"]]],
            ["type": "response.reasoning.search_results", "results": [["id": 7, "url": "https://example.com/a", "title": "Search"]]]
        ]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        let sources = parts.compactMap { part -> LanguageModelV4Source? in if case .source(let value) = part { return value }; return nil }
        let urls = sources.compactMap { source -> String? in if case .url(_, let url, _, _) = source { return url }; return nil }
        #expect(urls == ["https://example.com/a", "https://example.com/b", "https://example.com/c"])
        guard case .url(let id, _, let title, let metadata) = sources[0] else { Issue.record("Missing source"); return }
        #expect(id == "7")
        #expect(title == "Search")
        #expect(metadata?["perplexity"]?["resultId"] == 7)
    }

    @Test("function streams emit complete calls once and preserve thought signatures")
    func streamedFunction() async throws {
        let call: JSONValue = ["type": "function_call", "id": "item", "call_id": "call", "name": "weather", "arguments": "{}", "thought_signature": "signature"]
        let events: [JSONValue] = [["type": "response.output_item.done", "item": call], ["type": "response.completed", "response": .object(Self.response(output: [call], status: "requires_action"))]]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        #expect(Array(parts.dropFirst().dropLast().filter { if case .responseMetadata = $0 { return false }; return true }) == [
            .toolInputStart(id: "call", toolName: "weather", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil), .toolInputDelta(id: "call", delta: "{}", providerMetadata: nil), .toolInputEnd(id: "call", providerMetadata: nil),
            .toolCall(.init(toolCallId: "call", toolName: "weather", input: "{}", providerMetadata: ["perplexity": ["itemId": "item", "thoughtSignature": "signature"]]))
        ])
        guard case .finish(let finish, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish == .init(unified: .toolCalls, raw: "requires_action"))
    }

    @Test("reasoning events preserve lifecycle and thoughts across searches and fetches")
    func streamedReasoning() async throws {
        let events: [JSONValue] = [
            ["type": "response.reasoning.started", "sequence_number": 0, "thought": "Plan"],
            ["type": "response.reasoning.search_queries", "queries": ["query"], "thought": "Search"],
            ["type": "response.reasoning.fetch_url_queries", "urls": ["https://example.com"], "thought": "Fetch"],
            ["type": "response.reasoning.search_results", "results": .null, "thought": "Review"],
            ["type": "response.reasoning.started", "sequence_number": 1, "thought": .null],
            ["type": "response.reasoning.stopped", "thought": "Done"]
        ]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        #expect(Array(parts.dropFirst().dropLast()) == [
            .reasoningStart(id: "reasoning-0", providerMetadata: nil), .reasoningDelta(id: "reasoning-0", delta: "Plan", providerMetadata: nil), .reasoningDelta(id: "reasoning-0", delta: "Search", providerMetadata: nil), .reasoningDelta(id: "reasoning-0", delta: "Fetch", providerMetadata: nil), .reasoningDelta(id: "reasoning-0", delta: "Review", providerMetadata: nil), .reasoningEnd(id: "reasoning-0", providerMetadata: nil),
            .reasoningStart(id: "reasoning-1", providerMetadata: nil), .reasoningDelta(id: "reasoning-1", delta: "Done", providerMetadata: nil), .reasoningEnd(id: "reasoning-1", providerMetadata: nil)
        ])
    }

    @Test("known optional chunk fields validate even on unknown event types", arguments: [
        ["sequence_number": JSONValue.string("bad")], ["response": [:]], ["item": ["type": "message", "content": 1]], ["delta": 1],
        ["queries": [1]], ["urls": [false]], ["results": [["title": "Missing URL"]]],
        ["contents": [["title": "Title", "url": "https://example.com", "snippet": .null]]], ["error": ["message": "Error", "code": 1]]
    ])
    func malformedChunk(fields: JSONObject) async throws {
        var event = fields
        event["type"] = "future.event"
        let parts = try await collect(model(events: [.object(event)]).doStream(options: .init(prompt: prompt, includeRawChunks: true)))
        #expect(parts.contains(.raw(rawValue: .object(event))))
        let errors = parts.compactMap { part -> (any Error)? in if case .error(.error(let error)) = part { return error }; return nil }
        #expect(errors.first is TypeValidationError)
        guard case .finish(let finish, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish.unified == .error)
    }

    @Test("source and reasoning identifiers use ECMAScript number strings", arguments: [1e20, 1e-6, 1e-7, 1e21])
    func numericIdentifiers(number: Double) async throws {
        let expected = number == 1e20 ? "100000000000000000000" : number == 1e-6 ? "0.000001" : number == 1e-7 ? "1e-7" : "1e+21"
        let events: [JSONValue] = [
            ["type": "response.reasoning.started", "sequence_number": .number(number)],
            ["type": "response.reasoning.stopped"],
            ["type": "response.reasoning.search_results", "results": [["id": .number(number), "title": "Source", "url": "https://example.com"]]]
        ]
        let parts = try await collect(model(events: events).doStream(options: .init(prompt: prompt)))
        #expect(parts.contains(.reasoningStart(id: "reasoning-" + expected, providerMetadata: nil)))
        let identifiers = parts.compactMap { part -> String? in if case .source(.url(let id, _, _, _)) = part { return id }; return nil }
        #expect(identifiers == [expected])
    }

    @Test("stream failures preserve raw provider error fields")
    func failedStream() async throws {
        let error: JSONValue = ["message": "Agent failed", "type": "server_error", "code": .null, "future": true]
        let parts = try await collect(model(events: [["type": "response.failed", "error": error]]).doStream(options: .init(prompt: prompt)))
        #expect(parts.contains(.error(error: .value(error))))
        guard case .finish(let finish, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish == .init(unified: .error, raw: "failed"))
    }
}
