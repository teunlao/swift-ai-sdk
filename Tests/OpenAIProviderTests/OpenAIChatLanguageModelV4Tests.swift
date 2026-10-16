import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAI Chat contracts")
struct OpenAIChatContractTests {
    actor RequestCapture {
        private var requests: [URLRequest] = []

        func store(_ request: URLRequest) {
            requests.append(request)
        }

        func last() -> URLRequest? {
            requests.last
        }
    }

    @Test("V4 chat sends reasoning and provider reference file parts")
    func v4ChatSendsReasoningAndProviderReferenceFiles() async throws {
        let capture = RequestCapture()
        let responseData = try jsonData([
            "id": "chatcmpl-v4",
            "created": 1_711_115_037,
            "model": "gpt-4o-mini",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Hello from V4",
                        "tool_calls": [
                            [
                                "id": "call-1",
                                "type": "function",
                                "function": [
                                    "name": "lookup",
                                    "arguments": "{\"query\":\"swift\"}"
                                ]
                            ]
                        ],
                        "annotations": [
                            [
                                "type": "url_citation",
                                "url_citation": [
                                    "start_index": 0,
                                    "end_index": 5,
                                    "url": "https://example.com/doc",
                                    "title": "Example Doc"
                                ]
                            ]
                        ]
                    ],
                    "logprobs": [
                        "content": [
                            [
                                "token": "Hello",
                                "logprob": -0.01,
                                "top_logprobs": [["token": "Hello", "logprob": -0.01]]
                            ]
                        ]
                    ],
                    "finish_reason": "tool_calls"
                ]
            ],
            "usage": [
                "prompt_tokens": 8,
                "completion_tokens": 5,
                "total_tokens": 13,
                "completion_tokens_details": [
                    "accepted_prediction_tokens": 2,
                    "rejected_prediction_tokens": 1
                ]
            ]
        ])

        let provider = try createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let model: OpenAIChatLanguageModel = provider.chat("gpt-4o-mini")
        let result = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are helpful.", providerOptions: nil),
                .user(content: [
                    .text(.init(text: "Use the attached file.")),
                    .file(.init(
                        data: .reference(["openai": "file-openai-123"]),
                        mediaType: "application/pdf",
                        filename: "manual.pdf"
                    ))
                ], providerOptions: nil)
            ],
            reasoning: .medium,
            providerOptions: ["openai": ["logprobs": .number(1)]]
        ))

        #expect(model.specificationVersion == "v4")
        #expect(model.provider == "openai.chat")
        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.usage.inputTokens.total == 8)
        #expect(result.usage.outputTokens.total == 5)

        guard case .text(let text) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "Hello from V4")

        let toolCalls = result.content.compactMap { content -> LanguageModelV4ToolCall? in
            if case .toolCall(let toolCall) = content { return toolCall }
            return nil
        }
        #expect(toolCalls.first?.toolCallId == "call-1")
        #expect(toolCalls.first?.toolName == "lookup")
        #expect(toolCalls.first?.input == "{\"query\":\"swift\"}")

        let sources = result.content.compactMap { content -> LanguageModelV4Source? in
            if case .source(let source) = content { return source }
            return nil
        }
        guard case let .url(_, sourceURL, sourceTitle, _) = sources.first else {
            Issue.record("Expected URL source")
            return
        }
        #expect(sourceURL == "https://example.com/doc")
        #expect(sourceTitle == "Example Doc")

        let openAIMetadata = try #require(result.providerMetadata?["openai"])
        #expect(openAIMetadata["acceptedPredictionTokens"] == .number(2))
        #expect(openAIMetadata["rejectedPredictionTokens"] == .number(1))
        guard case .array(let logprobs)? = openAIMetadata["logprobs"] else {
            Issue.record("Expected V4 logprobs metadata to contain the OpenAI content array")
            return
        }
        #expect(logprobs.count == 1)

        let request = try #require(await capture.last())
        #expect(request.url?.absoluteString == "https://proxy.openai.example/v1/chat/completions")

        let body = try requestBodyJSON(request)
        #expect(body["model"] as? String == "gpt-4o-mini")
        #expect(body["reasoning_effort"] as? String == "medium")
        #expect(body["logprobs"] as? Bool == true)
        #expect(body["top_logprobs"] as? Int == 1)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[0]["role"] as? String == "system")
        let userContent = try #require(messages[1]["content"] as? [[String: Any]])
        let filePart = try #require(userContent.first { $0["type"] as? String == "file" })
        let fileObject = try #require(filePart["file"] as? [String: Any])
        #expect(fileObject["file_id"] as? String == "file-openai-123")
    }

    @Test("V4 chat sends GPT-5.6 max effort and reports cache writes")
    func v4ChatSendsGPT56MaxEffortAndReportsCacheWrites() async throws {
        let capture = RequestCapture()
        let provider = try createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(try jsonData([
                        "id": "chatcmpl-gpt-5-6",
                        "created": 1_711_115_037,
                        "model": "gpt-5.6-sol",
                        "choices": [[
                            "index": 0,
                            "message": ["role": "assistant", "content": "Done"],
                            "finish_reason": "stop"
                        ]],
                        "usage": [
                            "prompt_tokens": 100,
                            "completion_tokens": 12,
                            "total_tokens": 112,
                            "prompt_tokens_details": [
                                "cached_tokens": 40,
                                "cache_write_tokens": 20
                            ]
                        ]
                    ])),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let result = try await provider.chat("gpt-5.6-sol").doGenerate(options: .init(
            prompt: v4TextPrompt,
            providerOptions: [
                "openai": [
                    "reasoningEffort": .string("max"),
                    "promptCacheOptions": .object([
                        "mode": .string("explicit"),
                        "ttl": .string("30m")
                    ])
                ]
            ]
        ))

        #expect(result.usage.inputTokens.total == 100)
        #expect(result.usage.inputTokens.noCache == 40)
        #expect(result.usage.inputTokens.cacheRead == 40)
        #expect(result.usage.inputTokens.cacheWrite == 20)

        let body = try requestBodyJSON(try #require(await capture.last()))
        #expect(body["model"] as? String == "gpt-5.6-sol")
        #expect(body["reasoning_effort"] as? String == "max")
        let cacheOptions = try #require(body["prompt_cache_options"] as? [String: Any])
        #expect(cacheOptions["mode"] as? String == "explicit")
        #expect(cacheOptions["ttl"] as? String == "30m")
    }

    @Test("V4 chat streams V4 parts and includes usage stream options")
    func v4ChatStreamsPartsAndRequestShape() async throws {
        let capture = RequestCapture()
        let events = [
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"annotations":[{"type":"url_citation","url_citation":{"start_index":0,"end_index":5,"url":"https://example.com/source","title":"Source"}}]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call-stream","type":"function","function":{"name":"lookup","arguments":"{\"query\":\"swift\"}"}}]},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
            #"{"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1702657020,"model":"gpt-4o-mini","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":4,"total_tokens":13,"completion_tokens_details":{"accepted_prediction_tokens":3,"rejected_prediction_tokens":1}}}"#
        ]

        let provider = try createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: streamBody(from: events),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let model: OpenAIChatLanguageModel = provider.chat("gpt-4o-mini")
        let streamResult = try await model.doStream(options: .init(prompt: v4TextPrompt, includeRawChunks: false))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        #expect(parts.contains { if case .streamStart = $0 { return true }; return false })
        #expect(parts.contains {
            if case .responseMetadata(let id, let modelId, _) = $0 {
                return id == "chatcmpl-stream" && modelId == "gpt-4o-mini"
            }
            return false
        })
        #expect(parts.contains { if case .textStart(id: "0", providerMetadata: nil) = $0 { return true }; return false })
        #expect(parts.contains { if case .textDelta(id: "0", delta: "Hello", providerMetadata: nil) = $0 { return true }; return false })
        #expect(parts.contains { if case .textEnd(id: "0", providerMetadata: nil, citations: nil) = $0 { return true }; return false })
        #expect(parts.contains {
            if case .source(.url(_, "https://example.com/source", "Source", nil)) = $0 { return true }
            return false
        })
        #expect(parts.contains {
            if case .toolCall(let toolCall) = $0 {
                return toolCall.toolCallId == "call-stream"
                    && toolCall.toolName == "lookup"
                    && toolCall.input == "{\"query\":\"swift\"}"
            }
            return false
        })

        guard case let .finish(finishReason, usage, providerMetadata) = parts.last else {
            Issue.record("Expected finish as last stream part")
            return
        }
        #expect(finishReason.unified == .toolCalls)
        #expect(usage.inputTokens.total == 9)
        #expect(usage.outputTokens.total == 4)
        let metadata = try #require(providerMetadata?["openai"])
        #expect(metadata["acceptedPredictionTokens"] == .number(3))
        #expect(metadata["rejectedPredictionTokens"] == .number(1))

        let body = try requestBodyJSON(try #require(await capture.last()))
        #expect(body["stream"] as? Bool == true)
        let streamOptions = try #require(body["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test("V4 chat throws API error for OpenAI stream errors before output")
    func v4ChatThrowsPreOutputStreamErrors() async throws {
        let provider = try createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: streamBody(from: [
                        #"{"error":{"message":"The server had an error processing your request.","type":"server_error","param":null,"code":null}}"#
                    ]),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let model: OpenAIChatLanguageModel = provider.chat("gpt-4o-mini")

        do {
            _ = try await model.doStream(options: .init(prompt: v4TextPrompt, includeRawChunks: false))
            Issue.record("Expected APICallError before a stream result is returned")
        } catch let error as APICallError {
            #expect(error.message == "The server had an error processing your request.")
            #expect(error.statusCode == 500)
            #expect(error.isRetryable == true)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("V4 chat omits zero created timestamps like upstream metadata")
    func v4ChatOmitsZeroCreatedTimestamps() async throws {
        let generateResponse = try jsonData([
            "id": "chatcmpl-zero",
            "created": 0,
            "model": "gpt-4o-mini",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Zero timestamp"
                    ],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 2,
                "total_tokens": 3
            ]
        ])
        let streamEvents = [
            #"{"id":"chatcmpl-zero-stream","object":"chat.completion.chunk","created":0,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl-zero-stream","object":"chat.completion.chunk","created":0,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
            #"{"id":"chatcmpl-zero-stream","object":"chat.completion.chunk","created":0,"model":"gpt-4o-mini","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
        ]

        actor FetchState {
            private var calls = 0

            func nextResponse(for request: URLRequest, generateResponse: Data, streamEvents: [String]) -> FetchResponse {
                calls += 1
                if calls == 1 {
                    return FetchResponse(
                        body: .data(generateResponse),
                        urlResponse: HTTPURLResponse(
                            url: request.url!,
                            statusCode: 200,
                            httpVersion: "HTTP/1.1",
                            headerFields: ["Content-Type": "application/json"]
                        )!
                    )
                }

                return FetchResponse(
                    body: streamBody(from: streamEvents),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        }

        let state = FetchState()
        let provider = try createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await state.nextResponse(for: request, generateResponse: generateResponse, streamEvents: streamEvents)
            }
        ))

        let model: OpenAIChatLanguageModel = provider.chat("gpt-4o-mini")
        let generateResult = try await model.doGenerate(options: .init(prompt: v4TextPrompt))
        #expect(generateResult.response?.id == "chatcmpl-zero")
        #expect(generateResult.response?.modelId == "gpt-4o-mini")
        #expect(generateResult.response?.timestamp == nil)

        let streamResult = try await model.doStream(options: .init(prompt: v4TextPrompt, includeRawChunks: false))
        var metadataPart: LanguageModelV4StreamPart?
        for try await part in streamResult.stream {
            if case .responseMetadata = part {
                metadataPart = part
            }
        }

        guard case let .responseMetadata(id, modelId, timestamp) = metadataPart else {
            Issue.record("Expected response metadata part")
            return
        }
        #expect(id == "chatcmpl-zero-stream")
        #expect(modelId == "gpt-4o-mini")
        #expect(timestamp == nil)
    }
    @Test("portable reasoning respects provider precedence and GPT-6 sampling", arguments: [false, true])
    func portableReasoning(providerOverride: Bool) async throws {
        var providerOptions: [String: JSONValue] = ["promptCacheRetention": .string("24h"), "reasoningSummary": .string("auto")]
        if providerOverride { providerOptions["reasoningEffort"] = .string("high") }
        let exchange = try await chatExchange(options: .init(
            prompt: [], temperature: 0.4, reasoning: LanguageModelV4ReasoningEffort.none,
            providerOptions: ["openai": providerOptions]
        ), modelId: "gpt-6-sol")
        #expect(exchange.body["reasoning_effort"] == .string(providerOverride ? "high" : "none"))
        #expect(exchange.body["temperature"] == (providerOverride ? nil : .number(0.4)))
        #expect(exchange.body["prompt_cache_retention"] == nil)
        #expect(exchange.result.warnings.contains { if case .unsupported(feature: "promptCacheRetention", details: _) = $0 { return true }; return false })
        #expect(exchange.result.warnings.contains { if case .unsupported(feature: "reasoningSummary", details: _) = $0 { return true }; return false })
    }

    @Test("model capability parsing honors ASCII digits strict ends and large versions", arguments: ["gpt-6\n", "gpt-６", "gpt-99999999999999999999999999999"])
    func modelCapabilities(modelId: String) async throws {
        let exchange = try await chatExchange(options: .init(
            prompt: [], temperature: 0.4, reasoning: LanguageModelV4ReasoningEffort.none,
            providerOptions: ["openai": ["promptCacheRetention": .string("24h")]]
        ), modelId: modelId)
        let future = modelId.hasPrefix("gpt-999")
        #expect(exchange.body["temperature"] == (future ? nil : .number(0.4)))
        #expect(exchange.body["prompt_cache_retention"] == (future ? nil : .string("24h")))
        #expect(exchange.body["reasoning_effort"] == (future ? nil : .string("none")))
    }

    @Test("numeric logit bias keys use the coerced numeric identifiers")
    func logitBiasIdentifiers() async throws {
        let exchange = try await chatExchange(options: .init(prompt: [], providerOptions: ["openai": [
            "logitBias": .object([" 00012 ": .number(1), "0x10": .number(2), "": .number(3), "1e20": .number(4)]),
            "logprobs": .number(0), "serviceTier": .string("fast")
        ]]))
        #expect(exchange.body["logit_bias"] == .object(["12": .number(1), "16": .number(2), "0": .number(3), "100000000000000000000": .number(4)]))
        #expect(exchange.body["logprobs"] == .bool(true))
        #expect(exchange.body["top_logprobs"] == .number(0))
        #expect(exchange.body["service_tier"] == .string("fast"))
    }

    @Test("audio transcript fallback and usage details survive the response boundary")
    func audioAndUsage() async throws {
        let data = Data(#"{"choices":[{"index":0,"message":{"content":"","audio":{"transcript":"spoken"}},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":1,"total_tokens":null,"prompt_tokens_details":{"cached_tokens":2,"cache_write_tokens":4},"completion_tokens_details":{"reasoning_tokens":3}}}"#.utf8)
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "custom.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        let result = try await model.doGenerate(options: .init(prompt: []))
        #expect(result.content == [.text(.init(text: "spoken"))])
        #expect(result.usage.inputTokens.noCache == -1)
        #expect(result.usage.outputTokens.text == 0)
        #expect(result.usage.outputTokens.reasoning == 3)
        guard case .object(let raw)? = result.usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(raw["total_tokens"] == .null)
    }

    @Test("empty choices produce a typed invalid-response failure")
    func emptyChoices() async throws {
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: .data(Data(#"{"choices":[]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        await #expect(throws: InvalidResponseDataError.self) { _ = try await model.doGenerate(options: .init(prompt: [])) }
    }

    @Test("response parsing rejects invalid roles and incomplete function calls", arguments: [
        #"{"role":"user","content":"invalid"}"#,
        #"{"tool_calls":[{"type":"function","function":{"name":"missing-arguments"}}]}"#
    ])
    func invalidResponse(message: String) async throws {
        let data = Data(("{\"choices\":[{\"index\":0,\"message\":" + message + "}]}").utf8)
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        do {
            _ = try await model.doGenerate(options: .init(prompt: []))
            Issue.record("Expected response schema validation to fail")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.isRetryable == false)
        }
    }

    @Test("quota failures are nonretryable before and after output", arguments: [false, true])
    func quotaErrors(afterOutput: Bool) async throws {
        var events = [#"{"id":"accepted","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#]
        if afterOutput { events.append(#"{"choices":[{"index":0,"delta":{"content":"hello"}}]}"#) }
        events.append(#"{"error":{"message":"quota exhausted","type":"insufficient_quota","code":"insufficient_quota","param":null}}"#)
        let body = streamBody(from: events)
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        if afterOutput {
            let result = try await model.doStream(options: .init(prompt: []))
            let parts = try await convertReadableStreamToArray(result.stream)
            let error = try #require(parts.compactMap { part -> ProviderStreamError? in
                if case .error(.providerStreamError(let error)) = part { return error }; return nil
            }.first)
            #expect(error.isRetryable == false)
            #expect(error.statusCode == 429)
            guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
            #expect(reason.unified == .error)
        } else {
            do {
                _ = try await model.doStream(options: .init(prompt: []))
                Issue.record("Expected a pre-output API error")
            } catch let error as APICallError {
                #expect(error.isRetryable == false)
                #expect(error.statusCode == 429)
            }
        }
    }

    @Test("stream error decoding preserves explicit null without inventing absent fields", arguments: ["", "code", "param"])
    func errorPresence(field: String) async throws {
        let isClassified = !field.isEmpty
        var error: [String: JSONValue] = ["message": .string("wire failure")]
        if isClassified { error[field] = .null }
        let encoded = String(decoding: try JSONEncoder().encode(JSONValue.object(["error": .object(error)])), as: UTF8.self)
        let body = streamBody(from: [#"{"choices":[{"index":0,"delta":{"content":"hello"}}]}"#, encoded])
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let result = try await model.doStream(options: .init(prompt: []))
        let parts = try await convertReadableStreamToArray(result.stream)
        let errors = parts.compactMap { part -> LanguageModelV4StreamError? in
            if case .error(let error) = part { return error }; return nil
        }
        let received = try #require(errors.first)
        if isClassified {
            guard case .providerStreamError(let typed) = received else { Issue.record("Expected a typed provider error"); return }
            #expect(typed.data == .object(error))
        } else {
            guard case .value(let value) = received else { Issue.record("Expected the unclassified wire failure"); return }
            #expect(value == .object(error))
        }
        let preModel = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: streamBody(from: [encoded]), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        do {
            _ = try await preModel.doStream(options: .init(prompt: []))
            Issue.record("Expected a pre-output API error")
        } catch let failure as APICallError {
            #expect(failure.data as? JSONValue == .object(error))
            #expect((failure.message == "wire failure") == isClassified)
        }
    }

    @Test("a chunk matching both union members uses the data schema first")
    func streamUnionOrder() async throws {
        let body = streamBody(from: [#"{"choices":[{"index":0,"delta":{"content":"hello"}}],"error":{"message":"not the selected union member","code":500}}"#])
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let result = try await model.doStream(options: .init(prompt: []))
        let parts = try await convertReadableStreamToArray(result.stream)
        #expect(parts.contains(.textDelta(id: "0", delta: "hello", providerMetadata: nil)))
        #expect(!parts.contains { if case .error = $0 { return true }; return false })
    }

    @Test("canceling a Chat consumer closes the underlying response body", .timeLimit(.minutes(1)))
    func cancelConsumer() async throws {
        let (body, bodyContinuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let (closed, closedContinuation) = AsyncStream<Void>.makeStream()
        let (output, outputContinuation) = AsyncStream<Void>.makeStream()
        bodyContinuation.onTermination = { _ in closedContinuation.yield(()); closedContinuation.finish() }
        bodyContinuation.yield(Data(#"data: {"choices":[{"index":0,"delta":{"content":"hello"}}]}"#.utf8) + Data("\n\n".utf8))
        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: .init(provider: "openai.chat", url: { _ in "https://example.com/chat" }, fetch: { request in
            FetchResponse(body: .stream(body), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let consumer = Task {
            let result = try await model.doStream(options: .init(prompt: []))
            for try await part in result.stream {
                if case .textDelta(_, "hello", _) = part { outputContinuation.yield(()); outputContinuation.finish() }
            }
        }
        var outputIterator = output.makeAsyncIterator()
        #expect(await outputIterator.next() != nil)
        consumer.cancel()
        _ = try? await consumer.value
        var closedIterator = closed.makeAsyncIterator()
        #expect(await closedIterator.next() != nil)
    }
}

private let v4TextPrompt: LanguageModelV4Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func jsonData(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
}

private func requestBodyJSON(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func streamBody(from events: [String]) -> ProviderHTTPResponseBody {
    .stream(AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data("data: \(event)\n\n".utf8))
        }
        continuation.yield(Data("data: [DONE]\n\n".utf8))
        continuation.finish()
    })
}
