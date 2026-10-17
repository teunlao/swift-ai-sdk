import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import MoonshotAIProvider

@Suite("Moonshot native V4 contracts")
struct MoonshotAIChatContractsTests {
    private let empty = #"{"choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#
    private func model(_ id: String = "kimi-k3", payload: String? = nil, stream: Bool = false, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> MoonshotAIChatLanguageModel {
        let data = Data((payload ?? empty).utf8)
        return createMoonshotAI(settings: .init(apiKey: "key", fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"])!)
        }))(id)
    }
    private func stream(_ events: [String]) -> String { events.map { "data: \($0)\n\n" }.joined() + "data: [DONE]\n\n" }
    private static let reasoningCases: [(String, LanguageModelV4ReasoningEffort, JSONValue?, String?)] = [
        ("kimi-k2.5", .none, .object(["type": .string("disabled")]), nil),
        ("kimi-k2.6", .high, .object(["type": .string("enabled")]), nil),
        ("kimi-k2.7-code", .none, nil, nil),
        ("kimi-k3", .xhigh, nil, "max"),
        ("moonshot-v1-auto", .high, nil, nil),
        ("custom-model", .medium, nil, "high")
    ]

    @Test("model families map thinking and reasoning while suppressing fixed sampling", arguments: reasoningCases)
    func reasoningFamilies(_ id: String, _ reasoning: LanguageModelV4ReasoningEffort, _ thinking: JSONValue?, _ effort: String?) async throws {
        let result = try await model(id, inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["thinking"] == thinking)
            #expect(body["reasoning_effort"] == effort.map(JSONValue.string))
            #expect(body["max_completion_tokens"] == .number(23))
            #expect(body["temperature"] == (id.hasPrefix("kimi-") ? nil : .number(0.5)))
            #expect(body["top_p"] == (id.hasPrefix("kimi-") ? nil : .number(0.8)))
        }).doGenerate(options: .init(prompt: [], maxOutputTokens: 23, temperature: 0.5, topP: 0.8, reasoning: reasoning))
        if id == "kimi-k2.7-code" { #expect(result.warnings.contains { if case .unsupported(let feature, _) = $0 { feature == "reasoning \"none\"" } else { false } }) }
    }

    @Test("structured output and tool schemas use MFJS without changing the validation schema")
    func schemas() async throws {
        let schema: JSONValue = .object(["$schema": .string("https://json-schema.org/draft/2020-12/schema"), "type": .string("object"), "properties": .object([
            "tuple": .object(["type": .string("array"), "prefixItems": .array([.object(["type": .string("string")])]), "items": .array([.object(["type": .string("integer")])])]),
            "union": .object(["type": .string("string"), "anyOf": .array([.object(["enum": .array([.string("yes")])]), .object(["type": .string("null")])])])
        ])])
        let normalized: JSONValue = .object(["type": .string("object"), "properties": .object([
            "tuple": .object(["type": .string("array"), "prefixItems": .array([.object(["type": .string("string")]), .object(["type": .string("integer")])])]),
            "union": .object(["anyOf": .array([.object(["type": .string("string"), "enum": .array([.string("yes")])]), .object(["type": .string("null")])])])
        ])])
        _ = try await model("custom-model", inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["response_format"] == .object(["type": .string("json_schema"), "json_schema": .object(["name": .string("result"), "strict": .bool(false), "schema": normalized])]))
            guard case .array(let tools) = body["tools"], case .object(let first) = tools[0], case .object(let function) = first["function"] else { throw CancellationError() }
            #expect(function["strict"] == .bool(true))
            guard case .object(var expected) = normalized else { throw CancellationError() }
            expected["$schema"] = .string("https://json-schema.org/draft/2020-12/schema")
            #expect(function["parameters"] == .object(expected))
        }).doGenerate(options: .init(prompt: [], responseFormat: .json(schema: schema, name: "result", description: nil), tools: [.function(.init(name: "lookup", inputSchema: schema, strict: true))], providerOptions: ["moonshotai": ["strictJsonSchema": .bool(false)]]))
    }

    @Test("request options include logprobs prediction caching and explicit effort")
    func options() async throws {
        _ = try await model(inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["logprobs"] == .bool(true))
            #expect(body["top_logprobs"] == .number(20))
            #expect(body["reasoning_effort"] == .string("low"))
            #expect(body["prediction"] == .object(["type": .string("content"), "content": .array([.object(["type": .string("text"), "text": .string("known")])])]))
            #expect(body["prompt_cache_key"] == .string("cache"))
            #expect(body["safety_identifier"] == .string("safe"))
        }).doGenerate(options: .init(prompt: [], reasoning: .max, providerOptions: ["moonshotai": ["topLogprobs": .number(20), "reasoningEffort": .string("low"), "prediction": .object(["type": .string("content"), "content": .array([.object(["type": .string("text"), "text": .string("known")])])]), "promptCacheKey": .string("cache"), "safetyIdentifier": .string("safe")]]))
    }

    @Test("messages support dynamic tools partial continuation media references and reasoning replay")
    func messages() async throws {
        let dynamic: JSONValue = .object(["type": .string("function"), "name": .string("lookup"), "inputSchema": .object(["type": .string("object")])])
        let prompt: LanguageModelV4Prompt = [
            .system(content: "", providerOptions: ["moonshotai": ["tools": .array([dynamic])]]),
            .user(content: [
                .file(.init(data: .reference(["moonshotai": "ms://image"]), mediaType: "image/*")),
                .file(.init(data: .base64("dGV4dA=="), mediaType: "text/plain")),
                .file(.init(data: .data(Data([1, 2, 3])), mediaType: "video/mp4"))
            ], providerOptions: ["moonshotai": ["name": .string("user")]]),
            .assistant(content: [.reasoning(.init(text: "reason")), .text(.init(text: "partial"))], providerOptions: ["moonshotai": ["partial": .bool(true), "name": .string("assistant")]])
        ]
        let instance = model(inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            guard case .array(let messages) = body["messages"] else { throw CancellationError() }
            #expect(messages[0] == .object(["role": .string("system"), "tools": .array([.object(["type": .string("function"), "function": .object(["name": .string("lookup"), "parameters": .object(["type": .string("object")])])])])]))
            #expect(messages[1] == .object(["role": .string("user"), "name": .string("user"), "content": .array([
                .object(["type": .string("image_url"), "image_url": .object(["url": .string("ms://image")])]),
                .object(["type": .string("text"), "text": .string("text")]),
                .object(["type": .string("video_url"), "video_url": .object(["url": .string("data:video/mp4;base64,AQID")])])
            ])]))
            #expect(messages[2] == .object(["role": .string("assistant"), "name": .string("assistant"), "partial": .bool(true), "content": .string("partial"), "reasoning_content": .string("reason")]))
        })
        _ = try await instance.doGenerate(options: .init(prompt: prompt))
        let urls = try await instance.supportedUrls
        #expect(urls["image/*"]?.first?.firstMatch(in: "ms://image", range: NSRange(location: 0, length: 10)) != nil)
        #expect(urls["image/*"]?.first?.firstMatch(in: "https://example.com", range: NSRange(location: 0, length: 19)) == nil)
    }

    @Test("invalid partial prompt placement fails before HTTP", arguments: ["wrong-role", "not-final", "json-object", "dynamic-tools"])
    func invalidPrompts(_ mode: String) async throws {
        let instance = model(inspect: { _ in Issue.record("Invalid prompt cannot send HTTP") })
        let partial: SharedV4ProviderOptions = ["moonshotai": ["partial": .bool(true)]]
        var prompt: LanguageModelV4Prompt = [.assistant(content: [.text(.init(text: "a"))], providerOptions: partial)]
        if mode == "wrong-role" { prompt = [.user(content: [], providerOptions: partial)] }
        if mode == "not-final" { prompt.append(.user(content: [], providerOptions: nil)) }
        if mode == "dynamic-tools" { prompt = [.user(content: [], providerOptions: ["moonshotai": ["tools": .array([])]])] }
        let options = LanguageModelV4CallOptions(prompt: prompt, responseFormat: mode == "json-object" ? .json(schema: nil, name: nil, description: nil) : nil)
        await #expect(throws: InvalidPromptError.self) { _ = try await instance.doGenerate(options: options) }
    }

    @Test("unsupported file media and non-object schemas fail at the provider boundary")
    func invalidMediaAndSchema() async throws {
        let instance = model(inspect: { _ in Issue.record("Unsupported inputs cannot send HTTP") })
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await instance.doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: .data(Data([1])), mediaType: "application/pdf"))], providerOptions: nil)]))
        }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await instance.doGenerate(options: .init(prompt: [], tools: [.function(.init(name: "bad", inputSchema: .object(["type": .string("array")])))]))
        }
    }

    @Test("generate preserves content order logprobs metadata and raw usage")
    func generatedContent() async throws {
        let payload = #"{"id":"response","object":"chat.completion","created":1234,"model":"kimi-k3","choices":[{"index":2,"message":{"role":"assistant","reasoning_content":"reason","content":"answer","tool_calls":[{"id":"call","type":"function","function":{"name":"lookup","arguments":"{}"}}]},"logprobs":{"content":[{"token":"answer","logprob":-0.1,"bytes":null,"top_logprobs":[]}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":2,"cached_tokens":0,"prompt_tokens_details":{"cached_tokens":5,"future":7},"completion_tokens_details":{"reasoning_tokens":3}}}"#
        let result = try await model(payload: payload).doGenerate(options: .init(prompt: []))
        #expect(result.content == [.reasoning(.init(text: "reason")), .toolCall(.init(toolCallId: "call", toolName: "lookup", input: "{}")), .text(.init(text: "answer"))])
        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.usage.inputTokens.cacheRead == 0)
        #expect(result.usage.outputTokens.text == 0)
        #expect(result.providerMetadata?["moonshotai"]?["choiceIndex"] == .number(2))
        #expect(result.providerMetadata?["moonshotai"]?["responseObject"] == .string("chat.completion"))
        #expect(result.providerMetadata?["moonshotai"]?["toolCallTypes"] == .array([.string("function")]))
        #expect(result.providerMetadata?["moonshotai"]?["logprobs"] == .object(["content": .array([.object(["token": .string("answer"), "logprob": .number(-0.1), "bytes": .null, "top_logprobs": .array([])])])]))
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 1234))
    }

    @Test("anomalous usage remains raw without invalid integer counts", arguments: ["1e20", "0.5", "-9223372036854775808"])
    func anomalousUsage(_ count: String) async throws {
        let result = try await model(payload: "{\"choices\":[{\"message\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":\(count),\"cached_tokens\":1,\"completion_tokens\":1}}").doGenerate(options: .init(prompt: []))
        #expect(result.content == [.text(.init(text: "answer"))])
        #expect(result.usage.inputTokens.total == (count.hasPrefix("-") ? Int.min : nil))
        #expect(result.usage.inputTokens.noCache == nil)
        #expect(result.usage.outputTokens.total == 1)
        guard case .object(let raw) = result.usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(raw["prompt_tokens"] == .number(try #require(Double(count))))
    }

    @Test("streams indexless parallel tools by their array positions")
    func indexlessTools() async throws {
        let payload = stream([
            #"{"choices":[{"delta":{"tool_calls":[{"id":"a","type":"function","function":{"name":"lookup","arguments":"{\"city\":\""}},{"id":"b","type":"function","function":{"name":"lookup","arguments":"{\"city\":\""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"function":{"arguments":"Paris\"}"}},{"function":{"arguments":"Rome\"}"}}]},"finish_reason":"tool_calls"}]}"#
        ])
        let result = try await model(payload: payload, stream: true).doStream(options: .init(prompt: []))
        var calls: [LanguageModelV4ToolCall] = []
        for try await part in result.stream { if case .toolCall(let call) = part { calls.append(call) } }
        #expect(calls == [.init(toolCallId: "a", toolName: "lookup", input: #"{"city":"Paris"}"#), .init(toolCallId: "b", toolName: "lookup", input: #"{"city":"Rome"}"#)])
    }

    @Test("explicit tool indices correlate deltas independently of array order")
    func explicitToolIndices() async throws {
        let payload = stream([
            #"{"choices":[{"delta":{"tool_calls":[{"index":5,"id":"a","function":{"name":"lookup","arguments":"{\"v\":"}},{"index":2,"id":"b","function":{"name":"lookup","arguments":"{\"v\":"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":2,"function":{"arguments":"2}"}},{"index":5,"function":{"arguments":"5}"}}]},"finish_reason":"tool_calls"}]}"#
        ])
        let result = try await model(payload: payload, stream: true).doStream(options: .init(prompt: []))
        var calls: [String: String] = [:]
        for try await part in result.stream { if case .toolCall(let call) = part { calls[call.toolCallId] = call.input } }
        #expect(calls == ["a": #"{"v":5}"#, "b": #"{"v":2}"#])
    }

    @Test("root usage wins over later choice usage and reasoning ends when text begins")
    func streamUsage() async throws {
        let payload = stream([
            #"{"object":"chat.completion.chunk","choices":[{"index":1,"delta":{"role":"assistant","reasoning_content":"reason"},"usage":{"prompt_tokens":2,"completion_tokens":1}}]}"#,
            #"{"choices":[{"delta":{"content":"answer"}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"future":7}}"#,
            #"{"choices":[{"delta":{},"usage":{"prompt_tokens":99,"completion_tokens":99},"finish_reason":"stop"}]}"#
        ])
        let result = try await model(payload: payload, stream: true, inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["stream_options"] == .object(["include_usage": .bool(true)]))
        }).doStream(options: .init(prompt: [], includeRawChunks: true))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        let textStart = try #require(parts.firstIndex { if case .textStart = $0 { true } else { false } })
        #expect(parts[textStart + 1] == .reasoningEnd(id: "reasoning-0", providerMetadata: nil))
        guard case .finish(let finish, let usage, let metadata) = parts.last else { Issue.record("Missing finish"); return }
        #expect(finish.unified == .stop)
        #expect(usage.inputTokens.total == 10)
        #expect(metadata?["moonshotai"]?["choiceIndex"] == .number(1))
        #expect(metadata?["moonshotai"]?["messageRole"] == .string("assistant"))
        guard case .object(let raw) = usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(raw["future"] == .number(7))
    }

    @Test("malformed tool-call indices emit validation errors instead of using a fallback")
    func malformedToolIndex() async throws {
        let payload = stream([#"{"choices":[{"delta":{"tool_calls":[{"index":"bad","id":"a","function":{"name":"lookup","arguments":"{}"}}]}}]}"#])
        let result = try await model(payload: payload, stream: true).doStream(options: .init(prompt: []))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        #expect(parts.contains { if case .error(.error(let error)) = $0 { error is TypeValidationError } else { false } })
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .error)
    }

    @Test("choice-only usage and token logprobs survive stream aggregation")
    func choiceUsageAndLogprobs() async throws {
        let payload = stream([
            #"{"choices":[{"delta":{"content":"a"},"logprobs":{"content":[{"token":"a","logprob":-1,"bytes":null,"top_logprobs":[]}]}}]}"#,
            #"{"choices":[{"delta":{"content":"b"},"logprobs":{"content":[{"token":"b","logprob":-2,"bytes":[98],"top_logprobs":[]}]},"usage":{"prompt_tokens":4,"completion_tokens":2},"finish_reason":"stop"}]}"#
        ])
        let result = try await model(payload: payload, stream: true).doStream(options: .init(prompt: []))
        var finish: LanguageModelV4StreamPart?
        for try await part in result.stream { if case .finish = part { finish = part } }
        guard case .finish(_, let usage, let metadata) = finish else { Issue.record("Missing finish"); return }
        #expect(usage.inputTokens.total == 4)
        #expect(usage.outputTokens.total == 2)
        #expect(metadata?["moonshotai"]?["logprobs"] == .object(["content": .array([
            .object(["token": .string("a"), "logprob": .number(-1), "bytes": .null, "top_logprobs": .array([])]),
            .object(["token": .string("b"), "logprob": .number(-2), "bytes": .array([.number(98)]), "top_logprobs": .array([])])
        ])]))
    }

    @Test("invalid options reject before sending a request")
    func invalidOptions() async throws {
        let instance = model(inspect: { _ in Issue.record("Invalid options cannot send HTTP") })
        await #expect(throws: InvalidArgumentError.self) { _ = try await instance.doGenerate(options: .init(prompt: [], providerOptions: ["moonshotai": ["topLogprobs": .number(21)]])) }
    }

    @Test("provider stream errors expose status retry metadata and nullable raw codes", arguments: [false, true])
    func providerError(_ nullCode: Bool) async throws {
        let code: JSONValue = nullCode ? .null : .string("limit")
        let event: JSONValue = .object(["error": .object(["message": .string("rate limited"), "type": .string("rate_limit_exceeded"), "code": code, "extra": .bool(true)])])
        let payload = stream([String(decoding: try JSONEncoder().encode(event), as: UTF8.self)])
        let result = try await model(payload: payload, stream: true).doStream(options: .init(prompt: []))
        var errors: [ProviderStreamError] = []
        for try await part in result.stream { if case .error(.providerStreamError(let error)) = part { errors.append(error) } }
        let error = try #require(errors.first)
        #expect(error.message == "rate limited")
        #expect(error.statusCode == 429)
        #expect(error.isRetryable == true)
        #expect(error.code == (nullCode ? nil : .string("limit")))
        #expect(error.data == .object(["error": .object(["message": .string("rate limited"), "type": .string("rate_limit_exceeded"), "code": code])]))
    }
}
