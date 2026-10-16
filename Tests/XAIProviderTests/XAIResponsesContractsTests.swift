import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import XAIProvider

@Suite("xAI Responses V4 contracts")
struct XAIResponsesContractsTests {
    private func provider(_ payload: String, stream: Bool = false, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> XAIProvider {
        createXai(settings: .init(apiKey: "key", fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(Data(payload.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"])!)
        }))
    }

    @Test("request serializes files, reasoning replay, options, and strict function tools")
    func requestContracts() async throws {
        let provider = provider(#"{"object":"response","status":"completed","output":[]}"#) { request in
            guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!) else { Issue.record("Expected JSON request"); return }
            #expect(body["reasoning"] == .object(["effort": .string("xhigh")]))
            #expect(body["logprobs"] == .bool(true))
            #expect(body["top_logprobs"] == .number(8))
            #expect(body["top_k"] == .number(3))
            #expect(body["min_p"] == .number(0.2))
            #expect(body["max_turns"] == .number(4))
            #expect(body["parallel_tool_calls"] == .bool(false))
            #expect(body["prompt_cache_key"] == .string("cache"))
            #expect(body["safety_identifier"] == .string("safe"))
            #expect(body["service_tier"] == .string("priority"))
            #expect(body["user"] == .string("user"))
            #expect(body["store"] == .bool(false))
            #expect(body["tools"] == .array([.object(["type": .string("function"), "name": .string("weather"), "parameters": .object(["type": .string("object")]), "strict": .bool(true)])]))
            guard case .array(let input) = body["input"], case .object(let message) = input[0], case .array(let content) = message["content"], case .object(let replay) = input[1] else { Issue.record("Missing input"); return }
            #expect(content[0] == .object(["type": .string("input_file"), "file_id": .string("file-1")]))
            #expect(content[1] == .object(["type": .string("input_file"), "file_url": .string("https://example.com/report.pdf")]))
            #expect(content[2] == .object(["type": .string("input_image"), "image_url": .string("data:image/jpeg;base64,AQID"), "detail": .string("low")]))
            #expect(replay["encrypted_content"] == .string("cipher"))
            #expect(replay["id"] == .string("reason-1"))
            #expect(body["include"] == .array([.string("web_search_call.action.sources"), .string("reasoning.encrypted_content")]))
        }
        let prompt: LanguageModelV4Prompt = [
            .user(content: [
                .file(.init(data: .reference(["xai": "file-1"]), mediaType: "application/pdf")),
                .file(.init(data: .url(URL(string: "https://example.com/report.pdf")!), mediaType: "application/pdf")),
                .file(.init(data: .data(Data([1, 2, 3])), mediaType: "image/*", providerOptions: ["xai": ["imageDetail": .string("low")]]))
            ], providerOptions: nil),
            .assistant(content: [.reasoning(.init(text: "", providerOptions: ["xai": ["itemId": .string("reason-1"), "reasoningEncryptedContent": .string("cipher")]]))], providerOptions: nil)
        ]
        let tools: [LanguageModelV4Tool] = [.function(.init(name: "weather", inputSchema: .object(["type": .string("object")]), strict: true))]
        let options = LanguageModelV4CallOptions(prompt: prompt, topK: 3, tools: tools, reasoning: .max, providerOptions: ["xai": [
            "topLogprobs": .number(8), "minP": .number(0.2), "maxTurns": .number(4), "parallelToolCalls": .bool(false), "promptCacheKey": .string("cache"), "safetyIdentifier": .string("safe"), "serviceTier": .string("priority"), "user": .string("user"), "store": .bool(false), "include": .array([.string("web_search_call.action.sources")])
        ]])
        _ = try await provider.responses("grok-4.6").doGenerate(options: options)
    }

    @Test("provider responses preserve encrypted reasoning, function finish, and raw billing usage")
    func generationContracts() async throws {
        let payload = #"{"object":"response","status":"completed","output":[{"type":"reasoning","id":"r","summary":[],"status":"completed","encrypted_content":"cipher"},{"type":"function_call","id":"fc","call_id":"call","name":"weather","arguments":"{}"}],"usage":{"input_tokens":2,"output_tokens":3,"cost_in_usd_ticks":9,"future_usage":{"value":7},"input_tokens_details":{"cached_tokens":1,"future_cache":4}},"service_tier":"priority","prompt_cache_key":"cache","safety_identifier":"safe"}"#
        let result = try await provider(payload)("grok-4.6").doGenerate(options: .init(prompt: []))
        #expect(result.content[0] == .reasoning(.init(text: "", providerMetadata: ["xai": ["itemId": .string("r"), "reasoningEncryptedContent": .string("cipher")]])))
        #expect(result.finishReason.unified == .toolCalls)
        guard case .object(let raw) = result.usage.raw, case .object(let details) = raw["input_tokens_details"] else { Issue.record("Missing raw usage"); return }
        #expect(raw["future_usage"] == .object(["value": .number(7)]))
        #expect(details["future_cache"] == .number(4))
        #expect(result.providerMetadata == ["xai": ["costInUsdTicks": .number(9), "serviceTier": .string("priority"), "promptCacheKey": .string("cache"), "safetyIdentifier": .string("safe")]])
    }

    @Test("web search actions and image generation produce provider tool results")
    func providerResults() async throws {
        let payload = #"{"object":"response","status":"completed","output":[{"type":"web_search_call","id":"search","status":"completed","action":{"type":"open_page","url":"https://example.com","sources":[{"type":"url","url":"https://example.com"},{"type":"other"}]}},{"type":"image_generation_call","id":"image","status":"completed","result":"AQID","prompt":"otter"}]}"#
        let result = try await provider(payload)("grok-4.6").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: "xai.web_search", name: "searchWeb", args: [:])), .provider(.init(id: "xai.image_generation", name: "paint", args: [:]))]))
        #expect(result.content[1] == .toolResult(.init(toolCallId: "search", toolName: "searchWeb", result: .object(["action": .object(["type": .string("openPage"), "url": .string("https://example.com")]), "sources": .array([.object(["type": .string("url"), "url": .string("https://example.com")])])]))))
        #expect(result.content[3] == .toolResult(.init(toolCallId: "image", toolName: "paint", result: .object(["result": .string("AQID"), "prompt": .string("otter")]))))
    }

    @Test("stream errors expose provider retry metadata and incomplete finish")
    func streamErrors() async throws {
        let events = [#"{"type":"error","code":"insufficient_quota","message":"quota"}"#, #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":1,"output_tokens":2,"cost_in_usd_ticks":5}}}"#]
        let payload = events.map { "data: \($0)\n\n" }.joined()
        let result = try await provider(payload, stream: true)("grok-4.6").doStream(options: .init(prompt: []))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        guard case .error(.providerStreamError(let error)) = parts[1] else { Issue.record("Expected typed provider error"); return }
        #expect(error.statusCode == 429)
        #expect(error.isRetryable == false)
        #expect(error.message == "quota")
        guard case .finish(let reason, let usage, let metadata) = parts.last else { Issue.record("Expected finish"); return }
        #expect(reason == .init(unified: .length, raw: "max_output_tokens"))
        #expect(usage.outputTokens.total == 2)
        #expect(metadata?["xai"]?["costInUsdTicks"] == .number(5))
    }
}
