import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import FireworksProvider

@Suite("Fireworks native V4 contracts")
struct FireworksContractsTests {
    private func provider(_ payload: String, status: Int = 200, stream: Bool = false, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> FireworksProvider {
        createFireworks(settings: .init(apiKey: "key", fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(Data(payload.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"])!)
        }))
    }

    @Test("Fireworks options and structured output reach chat in wire format", arguments: [(LanguageModelV4ReasoningEffort.minimal, "low"), (.xhigh, "high"), (.max, "high")])
    func chatOptions(_ reasoning: LanguageModelV4ReasoningEffort, _ mapped: String) async throws {
        let api = provider(#"{"choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}"#, inspect: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["reasoning_effort"] == .string(mapped))
            #expect(body["thinking"] == .object(["type": .string("enabled"), "budget_tokens": .number(2048)]))
            #expect(body["reasoning_history"] == .string("preserved"))
            #expect(body["prompt_cache_key"] == .string("cache"))
            #expect(body["service_tier"] == .string("priority"))
            #expect(body["response_format"] == .object(["type": .string("json_schema"), "json_schema": .object(["name": .string("answer"), "strict": .bool(true), "schema": .object(["type": .string("object")])])]))
        })
        let result = try await api("model").doGenerate(options: .init(prompt: [], responseFormat: .json(schema: .object(["type": .string("object")]), name: "answer", description: nil), reasoning: reasoning, providerOptions: ["fireworks": ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(2048)]), "reasoningHistory": .string("preserved"), "promptCacheKey": .string("cache"), "serviceTier": .string("priority")]]))
        #expect(result.content == [.text(.init(text: "answer"))])
        #expect(result.warnings.contains { if case .compatibility(let feature, _) = $0 { feature == "reasoning" } else { false } })
    }

    @Test("chat and completion request stream usage", arguments: ["chat", "completion"])
    func streamingUsage(_ kind: String) async throws {
        let payload = kind == "chat" ? #"{"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}"# : #"{"choices":[{"index":0,"text":"answer","finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}"#
        let api = provider("data: \(payload)\n\ndata: [DONE]\n\n", stream: true, inspect: { request in
            #expect(request.url?.path.hasSuffix(kind == "chat" ? "/chat/completions" : "/completions") == true)
            let body = try JSONDecoder().decode(JSONObject.self, from: request.httpBody!)
            #expect(body["stream_options"] == .object(["include_usage": .bool(true)]))
        })
        let model: any LanguageModelV4 = kind == "chat" ? api.chatModel(modelId: "model") : api.completionModel(modelId: "model")
        let result = try await model.doStream(options: .init(prompt: [.user(content: [.text(.init(text: "hi"))], providerOptions: nil)]))
        var finish: LanguageModelV4StreamPart?
        for try await part in result.stream { if case .finish = part { finish = part } }
        guard case .finish(let reason, let usage, _) = finish else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.inputTokens.total == 2)
        #expect(usage.outputTokens.total == 1)
    }

    @Test("HTTP errors accept string and structured envelopes on every Compatible endpoint", arguments: ["chat", "completion", "embedding"])
    func httpErrors(_ kind: String) async throws {
        let payloads: [JSONValue] = [.string("invalid request"), .object(["message": .string("invalid request"), "object": .string("error"), "type": .string("invalid_request"), "param": .array([.string("model")]), "code": .number(400)])]
        for payload in payloads {
            let body = try JSONEncoder().encode(JSONValue.object(["error": payload]))
            let api = provider(String(decoding: body, as: UTF8.self), status: 400)
            do {
                if kind == "embedding" { _ = try await api.embeddingModel(modelId: "model").doEmbed(options: .init(values: ["text"])) }
                else {
                    let model: any LanguageModelV4 = kind == "chat" ? api.chatModel(modelId: "model") : api.completionModel(modelId: "model")
                    _ = try await model.doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "hi"))], providerOptions: nil)]))
                }
                Issue.record("Expected API failure")
            } catch let error as APICallError {
                #expect(error.message == "invalid request")
                #expect(error.statusCode == 400)
                #expect(try JSONDecoder().decode(JSONValue.self, from: Data(#require(error.responseBody).utf8)) == .object(["error": payload]))
            }
        }
    }

    @Test("stream errors preserve raw inner strings and objects", arguments: ["chat", "completion"])
    func streamErrors(_ kind: String) async throws {
        let payloads: [JSONValue] = [.string("failed"), .object(["message": .string("failed"), "type": .string("bad_request"), "param": .null, "code": .string("invalid"), "extra": .bool(true)])]
        for payload in payloads {
            let event = String(decoding: try JSONEncoder().encode(JSONValue.object(["error": payload])), as: UTF8.self)
            let api = provider("data: \(event)\n\ndata: [DONE]\n\n", stream: true)
            let model: any LanguageModelV4 = kind == "chat" ? api.chatModel(modelId: "model") : api.completionModel(modelId: "model")
            let result = try await model.doStream(options: .init(prompt: [.user(content: [.text(.init(text: "hi"))], providerOptions: nil)]))
            var errors: [JSONValue] = []
            for try await part in result.stream { if case .error(.value(let value)) = part { errors.append(value) } }
            #expect(errors == [payload])
        }
    }

    @Test("custom config and request Authorization override the loaded API key", arguments: [false, true])
    func authorizationPrecedence(_ requestHeader: Bool) async throws {
        let api = createFireworks(settings: .init(apiKey: "key", headers: ["Authorization": "Bearer config"], fetch: { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == (requestHeader ? "Bearer request" : "Bearer config"))
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-fireworks/") == true)
            return FetchResponse(body: .data(Data(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        let result = try await api("model").doGenerate(options: .init(prompt: [], headers: requestHeader ? ["Authorization": "Bearer request"] : nil))
        #expect(result.content == [.text(.init(text: "ok"))])
    }
}
