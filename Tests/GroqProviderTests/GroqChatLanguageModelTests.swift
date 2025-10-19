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
        #expect(result.usage.inputTokens == 12)
        #expect(result.usage.cachedInputTokens == 3)

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
        let warningFound = result.warnings.contains { warning in
            if case .unsupportedSetting(let setting, let details) = warning {
                return setting == "responseFormat" && details == "JSON response format schema is only supported with structuredOutputs"
            }
            return false
        }
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
        let warningFound = result.warnings.contains { warning in
            if case .unsupportedSetting(let setting, _) = warning {
                return setting == "topK"
            }
            return false
        }
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
                #expect(usage.inputTokens == 5)
                #expect(usage.outputTokens == 7)
            }
        } else {
        }
    }
}
