import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIChatLanguageModelV4")
struct OpenAIChatLanguageModelV4Tests {
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

        let provider = createOpenAI(settings: .init(
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

        let model: OpenAIChatLanguageModelV4 = provider.chat("gpt-4o-mini")
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

        let provider = createOpenAI(settings: .init(
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

        let model: OpenAIChatLanguageModelV4 = provider.chat("gpt-4o-mini")
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
        #expect(parts.contains { if case .textEnd(id: "0", providerMetadata: nil) = $0 { return true }; return false })
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
        let provider = createOpenAI(settings: .init(
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

        let model: OpenAIChatLanguageModelV4 = provider.chat("gpt-4o-mini")

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
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await state.nextResponse(for: request, generateResponse: generateResponse, streamEvents: streamEvents)
            }
        ))

        let model: OpenAIChatLanguageModelV4 = provider.chat("gpt-4o-mini")
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
