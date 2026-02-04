import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GroqProvider

@Suite("GroqChatLanguageModel")
struct GroqChatLanguageModelTests {
    private func makeConfig(fetch: @escaping FetchFunction, generateId: @escaping @Sendable () -> String = { UUID().uuidString }) -> GroqChatLanguageModel.Config {
        GroqChatLanguageModel.Config(
            provider: "groq.chat",
            url: { options in "https://api.groq.com/openai/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test"] },
            fetch: fetch,
            generateId: generateId
        )
    }

    private func decodeRequestBody(_ request: URLRequest) throws -> [String: Any] {
        guard let body = request.httpBody else { return [:] }
        return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    }

    private func makeSuccessfulResponse() -> (data: Data, response: HTTPURLResponse) {
        let responseJSON: [String: Any] = [
            "id": "resp-1",
            "created": 1_700_000_000.0,
            "model": "gemma",
            "choices": [[
                "message": [
                    "content": "Answer",
                    "reasoning": "Thought",
                    "tool_calls": [[
                        "id": "tool-1",
                        "type": "function",
                        "function": [
                            "name": "lookup",
                            "arguments": "{\"q\":\"rain\"}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]],
            "usage": [
                "prompt_tokens": 12,
                "completion_tokens": 7,
                "total_tokens": 19,
                "prompt_tokens_details": [
                    "cached_tokens": 3
                ]
            ]
        ]

        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return (data, response)
    }

    @Test("doGenerate maps response content")
    func generateMapping() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let generator = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch, generateId: { "generated" })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await generator.doGenerate(options: .init(prompt: prompt))

        #expect(result.content.contains { if case .text(let text) = $0 { return text.text == "Answer" } else { return false } })
        #expect(result.content.contains { if case .reasoning(let reasoning) = $0 { return reasoning.text == "Thought" } else { return false } })
        #expect(result.content.contains { if case .toolCall(let call) = $0 { return call.toolName == "lookup" && call.input == "{\"q\":\"rain\"}" } else { return false } })
        #expect(result.finishReason == .toolCalls)
        #expect(result.usage.inputTokens.total == 12)
        #expect(result.usage.inputTokens.cacheRead == nil)

        if let request = await capture.value() {
            let json = try decodeRequestBody(request)
            #expect(json["model"] as? String == "gemma")
        } else {
            Issue.record("Missing request")
        }
    }

    private func sseEvents(_ payloads: [String]) -> [String] {
        payloads.map { "data: \($0)\n\n" } + ["data: [DONE]\n\n"]
    }

    private func collect(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream {
            parts.append(part)
        }
        return parts
    }
    private func encodeJSON(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [])
        return String(data: data, encoding: .utf8)!
    }

    @Test("response format uses json_schema when structured outputs enabled")
    func responseFormatJsonSchema() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
        let schema: JSONValue = .object(["type": .string("object")])

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            responseFormat: .json(schema: schema, name: "Weather", description: "desc")
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        guard let responseFormat = json["response_format"] as? [String: Any] else {
            Issue.record("Missing response_format payload")
            return
        }
        #expect(responseFormat["type"] as? String == "json_schema")
        if let jsonSchema = responseFormat["json_schema"] as? [String: Any],
           let schemaValue = jsonSchema["schema"],
           let converted = try? jsonValue(from: schemaValue) {
            #expect(converted == schema)
            #expect(jsonSchema["name"] as? String == "Weather")
            #expect(jsonSchema["description"] as? String == "desc")
        } else {
            Issue.record("Missing json_schema payload")
        }
        #expect(result.warnings.isEmpty)
    }

    @Test("response format uses json_object when structured outputs disabled")
    func responseFormatJsonObjectWithoutStructuredOutputs() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
        let schema: JSONValue = .object(["type": .string("object")])

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            responseFormat: .json(schema: schema, name: nil, description: nil),
            providerOptions: ["groq": ["structuredOutputs": .bool(false)]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        guard let responseFormat = json["response_format"] as? [String: Any] else {
            Issue.record("Missing response_format payload")
            return
        }
        #expect(responseFormat["type"] as? String == "json_object")
        let warningFound = result.warnings.contains(where: { warning in
            if case .unsupported(let feature, let details) = warning {
                return feature == "responseFormat" && details == "JSON response format schema is only supported with structuredOutputs"
            }
            return false
        })
        #expect(warningFound)
    }

    @Test("provider options forwarded to Groq request")
    func providerOptionsForwarding() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
        let providerOptions: SharedV3ProviderOptions = [
            "groq": [
                "parallelToolCalls": .bool(false),
                "reasoningFormat": .string("parsed"),
                "reasoningEffort": .string("medium"),
                "user": .string("alice"),
                "serviceTier": .string("flex")
            ]
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            providerOptions: providerOptions
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["parallel_tool_calls"] as? Bool == false)
        #expect(json["reasoning_format"] as? String == "parsed")
        #expect(json["reasoning_effort"] as? String == "medium")
        #expect(json["user"] as? String == "alice")
        #expect(json["service_tier"] as? String == "flex")
    }

    @Test("topK produces unsupported setting warning")
    func topKWarning() async throws {
        let (responseData, httpResponse) = makeSuccessfulResponse()
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt, topK: 5))
        let warningFound = result.warnings.contains(where: { warning in
            if case .unsupported(let feature, _) = warning {
                return feature == "topK"
            }
            return false
        })
        #expect(warningFound)
    }

    @Test("missing tool call id throws invalid response error")
    func missingToolCallIdThrows() async throws {
        let events = sseEvents([
            encodeJSON([
                "choices": [
                    ["delta": [
                        "tool_calls": [[
                            "index": 0,
                            "function": [
                                "name": "lookup",
                                "arguments": "{\"foo\":1}"
                            ]
                        ]]
                    ]]
                ]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        do {
            _ = try await collect(result.stream)
            Issue.record("Expected stream to fail")
        } catch let error as InvalidResponseDataError {
            #expect(error.message.contains("Expected 'id'"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }


    @Test("doStream emits text, reasoning, tool events")
    func streamMapping() async throws {
        let payloads = [
            encodeJSON([
                "id": "chunk-1",
                "created": 1_700_000_000,
                "model": "gemma",
                "choices": [
                    ["delta": ["content": "Hel"]]
                ]
            ]),
            encodeJSON([
                "choices": [
                    ["delta": [
                        "content": "lo",
                        "tool_calls": [[
                            "index": 0,
                            "id": "call-1",
                            "function": [
                                "name": "lookup",
                                "arguments": "{\"q\":\"rain\"}"
                            ]
                        ]]
                    ]]
                ]
            ]),
            encodeJSON([
                "choices": [
                    ["delta": ["reasoning": " think"]]
                ]
            ]),
            encodeJSON([
                "choices": [
                    ["finish_reason": "stop"]
                ],
                "x_groq": [
                    "usage": [
                        "prompt_tokens": 5,
                        "completion_tokens": 7,
                        "total_tokens": 12
                    ]
                ]
            ])
        ]

        let events = sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma"),
            config: makeConfig(fetch: fetch, generateId: { "generated" })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt, includeRawChunks: true))
        let parts = try await collect(result.stream)

        #expect(parts.contains { if case .raw = $0 { return true } else { return false } })
        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0, delta == "Hel" { return true } else { return false } })
        #expect(parts.contains { if case .reasoningDelta(_, let delta, _) = $0, delta.contains("think") { return true } else { return false } })
        #expect(parts.contains { if case .toolCall(let call) = $0, call.toolName == "lookup" { return true } else { return false } })
        if let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) {
            if case let .finish(finishReason, usage, _) = finish {
                #expect(finishReason == .stop)
                #expect(usage.inputTokens.total == 5)
                #expect(usage.outputTokens.total == 7)
            }
        } else {
        }
    }

    @Test("should extract text")
    func extractText() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": "Hello, World!"],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.content.count == 1)
        if case let .text(text) = result.content[0] {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract reasoning")
    func extractReasoning() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["reasoning": "This is a test reasoning"],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.content.count == 1)
        if case let .reasoning(reasoning) = result.content[0] {
            #expect(reasoning.text == "This is a test reasoning")
        } else {
            Issue.record("Expected reasoning content")
        }
    }

    @Test("should extract usage")
    func extractUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 20, "completion_tokens": 5, "total_tokens": 25]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 5)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 25)
        #expect(result.usage.inputTokens.cacheRead == nil)
    }

    @Test("should send additional response information")
    func additionalResponseInfo() async throws {
        let responseJSON: [String: Any] = [
            "id": "test-id",
            "created": 123,
            "model": "test-model",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        guard let response = result.response else {
            Issue.record("Missing response")
            return
        }
        #expect(response.id == "test-id")
        #expect(response.timestamp == Date(timeIntervalSince1970: 123))
        #expect(response.modelId == "test-model")
    }

    @Test("should support partial usage")
    func partialUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 20, "total_tokens": 20]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 0)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 20)
        #expect(result.usage.inputTokens.cacheRead == nil)
    }

    @Test("should extract cached input tokens")
    func cachedInputTokens() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 20,
                "completion_tokens": 5,
                "total_tokens": 25,
                "prompt_tokens_details": ["cached_tokens": 15]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 5)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 25)
        #expect(result.usage.inputTokens.cacheRead == nil)
        if case let .object(raw)? = result.usage.raw,
           case let .object(promptTokensDetails)? = raw["prompt_tokens_details"],
           case let .number(cachedTokens)? = promptTokensDetails["cached_tokens"] {
            #expect(cachedTokens == 15)
        } else {
            Issue.record("Missing raw usage cached token data")
        }
    }

    @Test("should extract finish reason")
    func finishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.finishReason == .stop)
    }

    @Test("should support unknown finish reason")
    func unknownFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "eos"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.finishReason == .unknown)
    }

    @Test("should expose the raw response headers")
    func responseHeaders() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": ["content": ""],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "test-header": "test-value"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        guard let response = result.response else {
            Issue.record("Missing response")
            return
        }
        #expect(response.headers?["test-header"] == "test-value")
        #expect(response.headers?["content-type"] == "application/json")
    }

    @Test("should pass the model and the messages")
    func passModelAndMessages() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["model"] as? String == "gemma2-9b-it")
        if let messages = json["messages"] as? [[String: Any]],
           let firstMessage = messages.first {
            #expect(firstMessage["role"] as? String == "user")
            #expect(firstMessage["content"] as? String == "Hello")
        } else {
            Issue.record("Missing messages in request")
        }
    }

    @Test("should pass serviceTier provider option")
    func serviceTierProviderOption() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            providerOptions: ["groq": ["serviceTier": .string("flex")]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["service_tier"] as? String == "flex")
    }

    @Test("should pass tools and toolChoice")
    func passToolsAndToolChoice() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false)
            ]),
            description: nil
        ))

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            tools: [tool],
            toolChoice: .tool(toolName: "test-tool")
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["tools"] != nil)
        #expect(json["tool_choice"] != nil)
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = GroqChatLanguageModel.Config(
            provider: "groq.chat",
            url: { options in "https://api.groq.com/openai/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test", "Custom-Provider-Header": "provider-header-value"] },
            fetch: fetch,
            generateId: { UUID().uuidString }
        )

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: config
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }

    @Test("should parse tool results")
    func parseToolResults() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1700000000,
            "model": "gemma2-9b-it",
            "choices": [[
                "message": [
                    "content": "",
                    "tool_calls": [[
                        "id": "call_O17Uplv4lJvD6DVdIvFFeRMw",
                        "type": "function",
                        "function": [
                            "name": "test-tool",
                            "arguments": "{\"value\":\"Spark\"}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object(["type": .string("object")]),
            description: nil
        ))

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            tools: [tool],
            toolChoice: .tool(toolName: "test-tool")
        ))

        #expect(result.content.count == 1)
        if case let .toolCall(call) = result.content[0] {
            #expect(call.toolCallId == "call_O17Uplv4lJvD6DVdIvFFeRMw")
            #expect(call.toolName == "test-tool")
            #expect(call.input == "{\"value\":\"Spark\"}")
        } else {
            Issue.record("Expected tool call content")
        }
    }

    @Test("should use json_schema format when structuredOutputs explicitly enabled")
    func jsonSchemaExplicitlyEnabled() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
        let schema: JSONValue = .object(["type": .string("object")])

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            responseFormat: .json(schema: schema, name: "test-name", description: "test description"),
            providerOptions: ["groq": ["structuredOutputs": .bool(true)]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        guard let responseFormat = json["response_format"] as? [String: Any] else {
            Issue.record("Missing response_format")
            return
        }
        #expect(responseFormat["type"] as? String == "json_schema")
    }

    @Test("should allow explicit structuredOutputs override")
    func structuredOutputsOverride() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
        let schema: JSONValue = .object(["type": .string("object")])

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            responseFormat: .json(schema: schema, name: nil, description: nil),
            providerOptions: ["groq": ["structuredOutputs": .bool(true)]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        guard let responseFormat = json["response_format"] as? [String: Any],
              let jsonSchema = responseFormat["json_schema"] as? [String: Any] else {
            Issue.record("Missing response_format")
            return
        }
        #expect(responseFormat["type"] as? String == "json_schema")
        #expect(jsonSchema["name"] as? String == "response")
    }

    @Test("should send request body")
    func requestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = result.request else {
            Issue.record("Missing request")
            return
        }
        #expect(request.body != nil)
        if let bodyString = request.body as? String {
            #expect(bodyString.contains("gemma2-9b-it"))
            #expect(bodyString.contains("Hello"))
        }
    }

    @Test("should handle Kimi K2 model structured outputs")
    func kimiK2StructuredOutputs() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let (responseData, httpResponse) = makeSuccessfulResponse()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "moonshotai/kimi-k2-instruct"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Generate a simple recipe"))], providerOptions: nil)
        ]
        let schema: JSONValue = .object(["type": .string("object")])

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            responseFormat: .json(schema: schema, name: "recipe_response", description: "A recipe"),
            providerOptions: ["groq": ["structuredOutputs": .bool(true)]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["model"] as? String == "moonshotai/kimi-k2-instruct")
        #expect(json["response_format"] != nil)
    }

    @Test("should stream text deltas")
    func streamTextDeltas() async throws {
        let events = sseEvents([
            encodeJSON([
                "id": "chunk-1",
                "created": 1700000000,
                "model": "gemma2-9b-it",
                "choices": [[
                    "delta": ["content": "Hello"],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": ["content": " World"],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": [:],
                    "finish_reason": "stop"
                ]],
                "x_groq": [
                    "usage": [
                        "prompt_tokens": 5,
                        "completion_tokens": 2,
                        "total_tokens": 7
                    ]
                ]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)

        let hasHello = parts.contains { if case .textDelta(_, let delta, _) = $0, delta == "Hello" { return true } else { return false } }
        let hasWorld = parts.contains { if case .textDelta(_, let delta, _) = $0, delta == " World" { return true } else { return false } }
        #expect(hasHello)
        #expect(hasWorld)
    }

    @Test("should stream reasoning deltas")
    func streamReasoningDeltas() async throws {
        let events = sseEvents([
            encodeJSON([
                "id": "chunk-1",
                "created": 1700000000,
                "model": "gemma2-9b-it",
                "choices": [[
                    "delta": ["reasoning": "I think"],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": ["reasoning": " therefore"],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": [:],
                    "finish_reason": "stop"
                ]],
                "x_groq": [
                    "usage": [
                        "prompt_tokens": 5,
                        "completion_tokens": 2,
                        "total_tokens": 7
                    ]
                ]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)

        let hasThink = parts.contains { if case .reasoningDelta(_, let delta, _) = $0, delta.contains("think") { return true } else { return false } }
        let hasTherefore = parts.contains { if case .reasoningDelta(_, let delta, _) = $0, delta.contains("therefore") { return true } else { return false } }
        #expect(hasThink)
        #expect(hasTherefore)
    }

    @Test("should not duplicate tool calls on empty chunk")
    func streamNoDuplicateToolCalls() async throws {
        let events = sseEvents([
            encodeJSON([
                "id": "chunk-1",
                "created": 1700000000,
                "model": "gemma2-9b-it",
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "call-1",
                            "type": "function",
                            "function": [
                                "name": "lookup",
                                "arguments": "{\"q\":\"test\"}"
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": ["tool_calls": [[]]],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": [:],
                    "finish_reason": "tool_calls"
                ]],
                "x_groq": ["usage": ["prompt_tokens": 5, "completion_tokens": 10, "total_tokens": 15]]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)

        let toolCallCount = parts.filter { if case .toolCall = $0 { return true } else { return false } }.count
        #expect(toolCallCount == 1, "Should have exactly one tool call, not duplicates")
    }

    @Test("should pass stream messages and model")
    func streamMessagesAndModel() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let events = sseEvents([
            encodeJSON([
                "id": "chunk-1",
                "created": 1700000000,
                "model": "gemma2-9b-it",
                "choices": [[
                    "delta": ["content": "Hi"],
                    "finish_reason": NSNull()
                ]]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doStream(options: .init(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        let json = try decodeRequestBody(request)
        #expect(json["model"] as? String == "gemma2-9b-it")
        if let messages = json["messages"] as? [[String: Any]], let first = messages.first {
            #expect(first["role"] as? String == "user")
        } else {
            Issue.record("Missing messages")
        }
    }

    @Test("should pass stream headers")
    func streamHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let events = sseEvents([encodeJSON(["id": "1", "choices": [[:]]])])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let config = GroqChatLanguageModel.Config(
            provider: "groq.chat",
            url: { options in "https://api.groq.com/openai/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test", "Custom-Provider-Header": "provider-value"] },
            fetch: fetch,
            generateId: { UUID().uuidString }
        )

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: config
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doStream(options: .init(prompt: prompt, headers: ["Custom-Request-Header": "request-value"]))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalized["authorization"] == "Bearer test")
        #expect(normalized["custom-provider-header"] == "provider-value")
        #expect(normalized["custom-request-header"] == "request-value")
    }

    @Test("should send stream request body")
    func streamRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let events = sseEvents([encodeJSON(["id": "1", "choices": [[:]]])])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        _ = try await collect(result.stream)

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }
        guard let body = request.httpBody else {
            Issue.record("Missing request body")
            return
        }
        guard let bodyString = String(data: body, encoding: .utf8) else {
            Issue.record("Cannot decode body")
            return
        }
        #expect(bodyString.contains("gemma2-9b-it"))
        #expect(bodyString.contains("Hello"))
        #expect(bodyString.contains("\"stream\":true"))
    }

    @Test("should handle error stream parts")
    func streamErrorParts() async throws {
        let errorEvent = "data: " + encodeJSON([
            "error": [
                "message": "The server had an error processing your request. Sorry about that!",
                "type": "invalid_request_error"
            ]
        ]) + "\n\n"

        let doneEvent = "data: [DONE]\n\n"

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(Data(errorEvent.utf8))
                continuation.yield(Data(doneEvent.utf8))
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)

        // Verify stream start
        let hasStreamStart = parts.contains {
            if case .streamStart = $0 { return true } else { return false }
        }
        #expect(hasStreamStart)

        // Verify error part
        let hasError = parts.contains {
            if case .error(let error) = $0 {
                guard case let .object(errorObj) = error,
                      let errorValue = errorObj["error"],
                      case let .object(errorBody) = errorValue,
                      case let .string(message)? = errorBody["message"],
                      case let .string(type)? = errorBody["type"] else {
                    return false
                }
                return message == "The server had an error processing your request. Sorry about that!" &&
                       type == "invalid_request_error"
            }
            return false
        }
        #expect(hasError)

        // Verify finish with error reason
        let hasErrorFinish = parts.contains {
            if case .finish(let reason, _, _) = $0,
               case .error = reason {
                return true
            }
            return false
        }
        #expect(hasErrorFinish)
    }

    @Test("should stream tool call in one chunk")
    func streamToolCallOneChunk() async throws {
        let events = sseEvents([
            encodeJSON([
                "id": "chunk-1",
                "created": 1700000000,
                "model": "gemma2-9b-it",
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "call-1",
                            "type": "function",
                            "function": [
                                "name": "lookup",
                                "arguments": "{\"q\":\"test\"}"
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ]),
            encodeJSON([
                "choices": [[
                    "delta": [:],
                    "finish_reason": "tool_calls"
                ]],
                "x_groq": ["usage": ["prompt_tokens": 5, "completion_tokens": 10, "total_tokens": 15]]
            ])
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = GroqChatLanguageModel(
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it"),
            config: makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt))
        let parts = try await collect(result.stream)

        let hasToolCall = parts.contains { if case .toolCall(let call) = $0, call.toolName == "lookup" { return true } else { return false } }
        #expect(hasToolCall)
    }
}
