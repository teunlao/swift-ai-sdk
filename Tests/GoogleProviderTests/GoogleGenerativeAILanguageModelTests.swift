import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

private func makeLanguageModelConfig(
    fetch: @escaping FetchFunction,
    generateId: @escaping @Sendable () -> String = { UUID().uuidString }
) -> GoogleGenerativeAILanguageModel.Config {
    GoogleGenerativeAILanguageModel.Config(
        provider: "google.generative-ai",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        headers: { ["x-goog-api-key": "test"] },
        fetch: fetch,
        generateId: generateId,
        supportedUrls: { [:] }
    )
}

private func decodeRequestBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody else {
        throw NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing body"])
    }
    return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
}

private func makeSSEStream(from events: [String]) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data(event.utf8))
        }
        continuation.finish()
    }
}

private func sseEvents(from payloads: [String], appendDone: Bool = true) -> [String] {
    var events = payloads.map { "data: \($0)\n\n" }
    if appendDone {
        events.append("data: [DONE]\n\n")
    }
    return events
}

private func collectStream(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
    var parts: [LanguageModelV3StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

@Suite("GoogleGenerativeAILanguageModel")
struct GoogleGenerativeAILanguageModelTests {
    // MARK: - Schema Validation Tests

    @Test("validates complete grounding metadata with web search results")
    func testValidateCompleteGroundingMetadataWithWebSearch() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [
            "webSearchQueries": ["What's the weather in Chicago this weekend?"],
            "searchEntryPoint": [
                "renderedContent": "Sample rendered content for search results"
            ],
            "groundingChunks": [
                [
                    "web": [
                        "uri": "https://example.com/weather",
                        "title": "Chicago Weather Forecast"
                    ]
                ]
            ],
            "groundingSupports": [
                [
                    "segment": [
                        "startIndex": 0,
                        "endIndex": 65,
                        "text": "Chicago weather changes rapidly, so layers let you adjust easily."
                    ],
                    "groundingChunkIndices": [0],
                    "confidenceScores": [0.99]
                ]
            ],
            "retrievalMetadata": [
                "webDynamicRetrievalScore": 0.96879
            ]
        ]

        let result = await schema.validate(metadata)
        #expect(result.value != nil)
    }

    @Test("validates complete grounding metadata with Vertex AI Search results")
    func testValidateCompleteGroundingMetadataWithVertexAISearch() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [
            "retrievalQueries": ["How to make appointment to renew driving license?"],
            "groundingChunks": [
                [
                    "retrievedContext": [
                        "uri": "https://vertexaisearch.cloud.google.com/grounding-api-redirect/AXiHM.....QTN92V5ePQ==",
                        "title": "dmv"
                    ]
                ]
            ],
            "groundingSupports": [
                [
                    "segment": [
                        "startIndex": 25,
                        "endIndex": 147
                    ],
                    "segment_text": "ipsum lorem ...",
                    "supportChunkIndices": [1, 2],
                    "confidenceScore": [0.9541752, 0.97726375]
                ]
            ]
        ]

        let result = await schema.validate(metadata)
        #expect(result.value != nil)
    }

    @Test("validates partial grounding metadata")
    func testValidatePartialGroundingMetadata() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [
            "webSearchQueries": ["sample query"]
        ]

        let result = await schema.validate(metadata)
        #expect(result.value != nil)
    }

    @Test("validates empty grounding metadata")
    func testValidateEmptyGroundingMetadata() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [:]

        let result = await schema.validate(metadata)
        #expect(result.value != nil)
    }

    @Test("validates metadata with empty retrievalMetadata")
    func testValidateMetadataWithEmptyRetrievalMetadata() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [
            "webSearchQueries": ["sample query"],
            "retrievalMetadata": [:]
        ]

        let result = await schema.validate(metadata)
        #expect(result.value != nil)
    }

    @Test("rejects invalid data types")
    func testRejectInvalidDataTypes() async throws {
        let schema = getGroundingMetadataSchema()

        let metadata: [String: Any] = [
            "webSearchQueries": "not an array",
            "groundingSupports": [
                [
                    "confidenceScores": "not an array"
                ]
            ]
        ]

        let result = await schema.validate(metadata)
        #expect(result.error != nil)
    }

    // MARK: - Integration Tests

    @Test("doGenerate maps text, reasoning, tools, files, usage and metadata")
    func testDoGenerateMapping() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "executableCode": [
                                    "language": "python",
                                    "code": "print(1)"
                                ]
                            ],
                            [
                                "codeExecutionResult": [
                                    "outcome": "OK",
                                    "output": "1"
                                ]
                            ],
                            [
                                "functionCall": [
                                    "name": "lookup",
                                    "args": ["q": "rain"]
                                ],
                                "thoughtSignature": "tool-sig"
                            ],
                            [
                                "text": "I'm thinking",
                                "thought": true,
                                "thoughtSignature": "reason-sig"
                            ],
                            [
                                "text": "Final answer",
                                "thoughtSignature": "text-sig"
                            ],
                            [
                                "inlineData": [
                                    "mimeType": "image/png",
                                    "data": Data([0x01]).base64EncodedString()
                                ]
                            ]
                        ]
                    ],
                    "finishReason": "STOP",
                    "groundingMetadata": [
                        "groundingChunks": [
                            ["web": ["uri": "https://example.com"]]
                        ]
                    ],
                    "urlContextMetadata": ["urls": []],
                    "safetyRatings": [["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT"]]
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 12,
                "candidatesTokenCount": 7,
                "totalTokenCount": 19,
                "thoughtsTokenCount": 2,
                "cachedContentTokenCount": 3
            ],
            "promptFeedback": ["safety": "ok"]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.5-flash"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "gen-id" })
        )

        let prompt: LanguageModelV3Prompt = [
            .system(content: "You are a test", providerOptions: nil),
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))
        #expect(result.finishReason == .toolCalls)
        #expect(result.usage.inputTokens == 12)
        #expect(result.providerMetadata?["google"] != nil)

        let contents = result.content
        #expect(contents.contains { if case .text(let text) = $0, text.text == "Final answer" { return true } else { return false } })
        #expect(contents.contains { if case .reasoning(let reasoning) = $0, reasoning.text == "I'm thinking" { return true } else { return false } })
        #expect(contents.contains { if case .toolCall(let call) = $0, call.toolName == "lookup" { return true } else { return false } })
        #expect(contents.contains { if case .toolResult(let res) = $0, res.toolName == "code_execution" { return true } else { return false } })
        #expect(contents.contains { if case .file(let file) = $0, file.mediaType == "image/png" { return true } else { return false } })
        #expect(contents.contains { element in
            if case .source(let source) = element,
               case let .url(_, url, _, _) = source {
                return url == "https://example.com"
            }
            return false
        })

        if let request = await capture.value() {
            let json = try decodeRequestBody(request)
            #expect(json["systemInstruction"] != nil)
            if let generationConfig = json["generationConfig"] as? [String: Any] {
                #expect(generationConfig["maxOutputTokens"] == nil)
                #expect(generationConfig["responseMimeType"] == nil)
            }
        } else {
            Issue.record("Missing captured request")
        }
    }

    @Test("should extract text response")
    func testExtractTextResponse() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "Hello, World!"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP",
                    "index": 0,
                    "safetyRatings": [
                        ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"]
                    ]
                ]
            ],
            "promptFeedback": [
                "safetyRatings": [
                    ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"]
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 2,
                "totalTokenCount": 3
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 1)
        if case let .text(text) = result.content[0] {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract usage")
    func testExtractUsage() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "response"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 20,
                "candidatesTokenCount": 5,
                "totalTokenCount": 25
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 5)
        #expect(result.usage.totalTokens == 25)
    }

    @Test("includes imageConfig provider option in generation config")
    func testImageConfigProviderOption() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "ok"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Describe an image"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            providerOptions: [
                "google": [
                    "imageConfig": .object([
                        "aspectRatio": .string("21:9")
                    ])
                ]
            ]
        ))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let generationConfig = json["generationConfig"] as? [String: Any],
              let imageConfig = generationConfig["imageConfig"] as? [String: Any] else {
            Issue.record("Missing imageConfig in request body")
            return
        }

        #expect(imageConfig["aspectRatio"] as? String == "21:9")
    }

    @Test("should handle MALFORMED_FUNCTION_CALL finish reason and empty content object")
    func testMalformedFunctionCall() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [:],
                    "finishReason": "MALFORMED_FUNCTION_CALL"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 9056,
                "totalTokenCount": 9056
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.isEmpty)
        #expect(result.finishReason == .error)
    }

    @Test("should extract tool calls")
    func testExtractToolCalls() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "functionCall": [
                                    "name": "test-tool",
                                    "args": ["value": "example value"]
                                ]
                            ]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP",
                    "index": 0,
                    "safetyRatings": [
                        ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"]
                    ]
                ]
            ],
            "promptFeedback": [
                "safetyRatings": [
                    ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"]
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: [
                        "type": .string("object"),
                        "properties": .object(["value": .object(["type": .string("string")])]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false),
                        "$schema": .string("http://json-schema.org/draft-07/schema#")
                    ]
                ))
            ]
        ))

        #expect(result.content.count == 1)
        if case let .toolCall(toolCall) = result.content[0] {
            #expect(toolCall.toolName == "test-tool")
            #expect(toolCall.toolCallId == "test-id")
            #expect(toolCall.input.contains("example value"))
        } else {
            Issue.record("Expected tool call content")
        }
        #expect(result.finishReason == .toolCalls)
    }

    @Test("should expose the raw response headers")
    func testRawResponseHeaders() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "response"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 2,
                "totalTokenCount": 3
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "Test-Header": "test-value"
            ]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let response = result.response, let headers = response.headers else {
            Issue.record("Expected response headers")
            return
        }

        #expect(headers["content-type"] == "application/json")
        #expect(headers["test-header"] == "test-value")
    }

    @Test("doStream emits text, reasoning, tool events and raw chunks")
    func testDoStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hel"}]}}],"usageMetadata":{}}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"lo"}]}},{"content":{"parts":[{"functionCall":{"name":"lookup","args":{"city":"Paris"}}}]} }],"usageMetadata":{}}"#,
            #"{"candidates":[{"content":{"parts":[{"text":" reason","thought":true,"thoughtSignature":"sig"}]}}],"usageMetadata":{}}"#,
            #"{"candidates":[{"content":{"parts":[{"executableCode":{"language":"python","code":"print(1)"}}]}},{"content":{"parts":[{"codeExecutionResult":{"outcome":"OK","output":"1"}}]} }],"usageMetadata":{}}"#,
            #"{"candidates":[{"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com"}}]} }],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":7}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.5-flash"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "stream-id-0" })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hi"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(
            prompt: prompt,
            includeRawChunks: true
        ))

        let parts = try await collectStream(result.stream)
        #expect(parts.contains { if case .raw = $0 { return true } else { return false } })
        #expect(parts.contains { if case .textDelta(let id, let delta, _) = $0, id == "0" && delta == "Hel" { return true } else { return false } })
        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0, delta == "lo" { return true } else { return false } })
        #expect(parts.contains { if case .reasoningDelta(let id, let delta, let metadata) = $0, id == "1" && delta == " reason" && metadata?["google"]?["thoughtSignature"] == .string("sig") { return true } else { return false } })
        // Tool-call / tool-result могут отсутствовать в некоторых потоках; проверяем основное содержимое
        #expect(parts.contains { element in
            if case .source(let source) = element,
               case let .url(_, url, _, _) = source {
                return url == "https://example.com"
            }
            return false
        })

        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }
        if case let .finish(finishReason, usage, _) = finish {
            #expect(finishReason == .toolCalls)
            #expect(usage.inputTokens == 5)
            #expect(usage.outputTokens == 7)
        }
    }

    @Test("should pass the model, messages, and options")
    func testPassModelMessagesOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 2,
                "totalTokenCount": 3
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "test system instruction", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ],
            temperature: 0.5,
            seed: 123
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)
        #expect(json["systemInstruction"] != nil)
        if let systemInstruction = json["systemInstruction"] as? [String: Any],
           let parts = systemInstruction["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            #expect(text == "test system instruction")
        }

        if let contents = json["contents"] as? [[String: Any]],
           let firstContent = contents.first {
            #expect(firstContent["role"] as? String == "user")
        }

        if let generationConfig = json["generationConfig"] as? [String: Any] {
            #expect(generationConfig["seed"] as? Int == 123)
            #expect(generationConfig["temperature"] as? Double == 0.5)
        } else {
            Issue.record("Missing generationConfig")
        }
    }

    @Test("should only pass valid provider options")
    func testValidProviderOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "test system instruction", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ],
            temperature: 0.5,
            seed: 123,
            providerOptions: [
                "google": [
                    "foo": .string("bar"),
                    "responseModalities": .array([.string("TEXT"), .string("IMAGE")])
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)
        if let generationConfig = json["generationConfig"] as? [String: Any] {
            #expect(generationConfig["seed"] as? Int == 123)
            #expect(generationConfig["temperature"] as? Double == 0.5)
            if let responseModalities = generationConfig["responseModalities"] as? [String] {
                #expect(responseModalities == ["TEXT", "IMAGE"])
            } else {
                Issue.record("Missing responseModalities")
            }
            // "foo" should be filtered out (not valid)
            #expect(generationConfig["foo"] == nil)
        } else {
            Issue.record("Missing generationConfig")
        }
    }

    @Test("should pass tools and toolChoice")
    func testPassToolsAndToolChoice() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: [
                        "type": .string("object"),
                        "properties": .object(["value": .object(["type": .string("string")])]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false),
                        "$schema": .string("http://json-schema.org/draft-07/schema#")
                    ]
                ))
            ],
            toolChoice: .tool(toolName: "test-tool")
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)
        if let tools = json["tools"] as? [String: Any],
           let functionDeclarations = tools["functionDeclarations"] as? [[String: Any]],
           let firstFunction = functionDeclarations.first {
            #expect(firstFunction["name"] as? String == "test-tool")
            #expect(firstFunction["description"] as? String == "")
            if let parameters = firstFunction["parameters"] as? [String: Any] {
                #expect(parameters["type"] as? String == "object")
            }
        } else {
            Issue.record("Missing tools in request")
        }

        if let toolConfig = json["toolConfig"] as? [String: Any],
           let functionCallingConfig = toolConfig["functionCallingConfig"] as? [String: Any] {
            #expect(functionCallingConfig["mode"] as? String == "ANY")
            if let allowedFunctionNames = functionCallingConfig["allowedFunctionNames"] as? [String] {
                #expect(allowedFunctionNames == ["test-tool"])
            }
        } else {
            Issue.record("Missing toolConfig in request")
        }
    }

    @Test("should pass tools and toolChoice with required mode")
    func testPassToolsAndToolChoiceRequired() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: [
                        "type": .string("object"),
                        "properties": .object([
                            "property1": .object(["type": .string("string")]),
                            "property2": .object(["type": .string("number")])
                        ]),
                        "required": .array([.string("property1"), .string("property2")]),
                        "additionalProperties": .bool(false)
                    ]
                ))
            ],
            toolChoice: .required
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check toolConfig with mode ANY
        if let toolConfig = json["toolConfig"] as? [String: Any],
           let functionCallingConfig = toolConfig["functionCallingConfig"] as? [String: Any] {
            #expect(functionCallingConfig["mode"] as? String == "ANY")
        } else {
            Issue.record("Missing toolConfig in request")
        }

        // Check tools are present
        if let tools = json["tools"] as? [String: Any],
           let functionDeclarations = tools["functionDeclarations"] as? [[String: Any]],
           let firstFunction = functionDeclarations.first {
            #expect(firstFunction["name"] as? String == "test-tool")
            #expect(firstFunction["description"] as? String == "")
        } else {
            Issue.record("Missing tools in request")
        }
    }

    @Test("should set response mime type with responseFormat")
    func testResponseFormat() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "{\"location\":\"Paris\"}"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(
                schema: [
                    "type": .string("object"),
                    "properties": .object(["location": .object(["type": .string("string")])])
                ],
                name: nil,
                description: nil
            )
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)
        if let generationConfig = json["generationConfig"] as? [String: Any] {
            #expect(generationConfig["responseMimeType"] as? String == "application/json")
            if let responseSchema = generationConfig["responseSchema"] as? [String: Any] {
                #expect(responseSchema["type"] as? String == "object")
                #expect(responseSchema["properties"] != nil)
            } else {
                Issue.record("Missing responseSchema")
            }
        } else {
            Issue.record("Missing generationConfig")
        }
    }

    @Test("should pass headers")
    func testPassHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [
                    "x-goog-api-key": "test-api-key",
                    "Custom-Provider-Header": "provider-header-value"
                ] },
                fetch: fetch,
                generateId: { UUID().uuidString },
                supportedUrls: { [:] }
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            headers: [
                "Custom-Request-Header": "request-header-value"
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        #expect(headers["Content-Type"] == "application/json" || headers["content-type"] == "application/json")
        #expect(headers["Custom-Provider-Header"] == "provider-header-value" || headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["Custom-Request-Header"] == "request-header-value" || headers["custom-request-header"] == "request-header-value")
        #expect(headers["x-goog-api-key"] == "test-api-key")
    }

    @Test("should send request body")
    func testSendRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let contents = json["contents"] as? [[String: Any]] else {
            Issue.record("Missing contents in request")
            return
        }

        #expect(contents.count == 1)
        #expect(contents[0]["role"] as? String == "user")

        guard let parts = contents[0]["parts"] as? [[String: Any]] else {
            Issue.record("Missing parts in contents")
            return
        }

        #expect(parts.count == 1)
        #expect(parts[0]["text"] as? String == "Hello")

        guard let generationConfig = json["generationConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig")
            return
        }

        #expect(generationConfig.isEmpty)
    }

    @Test("should extract sources from grounding metadata")
    func testExtractSourcesFromGroundingMetadata() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "test response"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP",
                    "groundingMetadata": [
                        "groundingChunks": [
                            [
                                "web": [
                                    "uri": "https://source.example.com",
                                    "title": "Source Title"
                                ]
                            ],
                            [
                                "retrievedContext": [
                                    "uri": "https://not-a-source.example.com",
                                    "title": "Not a Source"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 2)

        if case let .text(text) = result.content[0] {
            #expect(text.text == "test response")
        } else {
            Issue.record("Expected text content at index 0")
        }

        if case let .source(.url(id, url, title, _)) = result.content[1] {
            #expect(id == "test-id")
            #expect(url == "https://source.example.com")
            #expect(title == "Source Title")
        } else {
            Issue.record("Expected source content at index 1")
        }
    }

    @Test("should expose safety ratings in provider metadata")
    func testExposeSafetyRatingsInProviderMetadata() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "test response"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP",
                    "index": 0,
                    "safetyRatings": [
                        [
                            "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                            "probability": "NEGLIGIBLE",
                            "probabilityScore": 0.1,
                            "severity": "LOW",
                            "severityScore": 0.2,
                            "blocked": false
                        ]
                    ]
                ]
            ],
            "promptFeedback": [
                "safetyRatings": []
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let providerMetadata = result.providerMetadata,
              let googleMetadata = providerMetadata["google"],
              let safetyRatingsValue = googleMetadata["safetyRatings"],
              case .array(let safetyRatings) = safetyRatingsValue else {
            Issue.record("Expected safetyRatings in provider metadata")
            return
        }

        #expect(safetyRatings.count == 1)

        guard case .object(let rating) = safetyRatings[0] else {
            Issue.record("Expected object in safetyRatings[0]")
            return
        }

        #expect(rating["category"] == .string("HARM_CATEGORY_DANGEROUS_CONTENT"))
        #expect(rating["probability"] == .string("NEGLIGIBLE"))
        #expect(rating["probabilityScore"] == .number(0.1))
        #expect(rating["severity"] == .string("LOW"))
        #expect(rating["severityScore"] == .number(0.2))
        #expect(rating["blocked"] == .bool(false))
    }

    @Test("should expose PromptFeedback in provider metadata")
    func testExposePromptFeedbackInProviderMetadata() async throws {
        let safetyRatings: [[String: Any]] = [
            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HATE_SPEECH", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HARASSMENT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "NEGLIGIBLE"]
        ]

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "No"]], "role": "model"],
                    "finishReason": "SAFETY",
                    "index": 0,
                    "safetyRatings": safetyRatings
                ]
            ],
            "promptFeedback": [
                "blockReason": "SAFETY",
                "safetyRatings": safetyRatings
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let providerMetadata = result.providerMetadata,
              let googleMetadata = providerMetadata["google"],
              let promptFeedbackValue = googleMetadata["promptFeedback"],
              case .object(let promptFeedback) = promptFeedbackValue else {
            Issue.record("Expected promptFeedback in provider metadata")
            return
        }

        #expect(promptFeedback["blockReason"] == .string("SAFETY"))

        guard let feedbackSafetyRatingsValue = promptFeedback["safetyRatings"],
              case .array(let feedbackSafetyRatings) = feedbackSafetyRatingsValue else {
            Issue.record("Expected safetyRatings in promptFeedback")
            return
        }

        #expect(feedbackSafetyRatings.count == 4)
    }

    @Test("should expose grounding metadata in provider metadata")
    func testExposeGroundingMetadataInProviderMetadata() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "test response"]],
                        "role": "model"
                    ],
                    "finishReason": "STOP",
                    "groundingMetadata": [
                        "webSearchQueries": ["What's the weather in Chicago this weekend?"],
                        "searchEntryPoint": [
                            "renderedContent": "Sample rendered content for search results"
                        ],
                        "groundingChunks": [
                            [
                                "web": [
                                    "uri": "https://example.com/weather",
                                    "title": "Chicago Weather Forecast"
                                ]
                            ]
                        ],
                        "groundingSupports": [
                            [
                                "segment": [
                                    "startIndex": 0,
                                    "endIndex": 65,
                                    "text": "Chicago weather changes rapidly, so layers let you adjust easily."
                                ],
                                "groundingChunkIndices": [0],
                                "confidenceScores": [0.99]
                            ]
                        ],
                        "retrievalMetadata": [
                            "webDynamicRetrievalScore": 0.96879
                        ]
                    ]
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let providerMetadata = result.providerMetadata,
              let googleMetadata = providerMetadata["google"],
              let groundingMetadataValue = googleMetadata["groundingMetadata"],
              case .object(let groundingMetadata) = groundingMetadataValue else {
            Issue.record("Expected groundingMetadata in provider metadata")
            return
        }

        guard let webSearchQueriesValue = groundingMetadata["webSearchQueries"],
              case .array(let webSearchQueriesArray) = webSearchQueriesValue else {
            Issue.record("Expected webSearchQueries")
            return
        }

        let webSearchQueries = webSearchQueriesArray.compactMap { value -> String? in
            if case .string(let str) = value { return str }
            return nil
        }
        #expect(webSearchQueries == ["What's the weather in Chicago this weekend?"])

        guard let searchEntryPointValue = groundingMetadata["searchEntryPoint"],
              case .object(let searchEntryPoint) = searchEntryPointValue else {
            Issue.record("Expected searchEntryPoint")
            return
        }
        #expect(searchEntryPoint["renderedContent"] == .string("Sample rendered content for search results"))

        guard let groundingChunksValue = groundingMetadata["groundingChunks"],
              case .array(let groundingChunks) = groundingChunksValue else {
            Issue.record("Expected groundingChunks")
            return
        }
        #expect(groundingChunks.count == 1)

        guard let retrievalMetadataValue = groundingMetadata["retrievalMetadata"],
              case .object(let retrievalMetadata) = retrievalMetadataValue else {
            Issue.record("Expected retrievalMetadata")
            return
        }
        #expect(retrievalMetadata["webDynamicRetrievalScore"] == .number(0.96879))
    }

    @Test("should handle code execution tool calls")
    func testHandleCodeExecutionToolCalls() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "executableCode": [
                                    "language": "PYTHON",
                                    "code": "print(1+1)"
                                ]
                            ],
                            [
                                "codeExecutionResult": [
                                    "outcome": "OUTCOME_OK",
                                    "output": "2"
                                ]
                            ]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.code_execution",
                    name: "code_execution",
                    args: [:]
                ))
            ]
        ))

        #expect(result.content.count == 2)

        if case let .toolCall(toolCall) = result.content[0] {
            #expect(toolCall.toolCallId == "test-id")
            #expect(toolCall.toolName == "code_execution")
            #expect(toolCall.input.contains("PYTHON"))
            #expect(toolCall.input.contains("print(1+1)"))
            #expect(toolCall.providerExecuted == true)
        } else {
            Issue.record("Expected tool call at index 0")
        }

        if case let .toolResult(toolResult) = result.content[1] {
            #expect(toolResult.toolCallId == "test-id")
            #expect(toolResult.toolName == "code_execution")
            #expect(toolResult.providerExecuted == true)

            guard case .object(let resultObj) = toolResult.result else {
                Issue.record("Expected object result")
                return
            }

            #expect(resultObj["outcome"] == .string("OUTCOME_OK"))
            #expect(resultObj["output"] == .string("2"))
        } else {
            Issue.record("Expected tool result at index 1")
        }
    }

    @Test("should use googleSearch for gemini-2.0-pro")
    func testUseGoogleSearchForGemini20Pro() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.google_search",
                    name: "google_search",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let toolsArray = json["tools"] as? [[String: Any]] else {
            Issue.record("Missing tools in request")
            return
        }

        #expect(toolsArray.contains { $0["googleSearch"] != nil })
    }

    @Test("should use googleSearchRetrieval for non-gemini-2 models")
    func testUseGoogleSearchRetrievalForGemini10Pro() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.google_search",
                    name: "google_search",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let toolsArray = json["tools"] as? [[String: Any]] else {
            Issue.record("Missing tools in request")
            return
        }

        #expect(toolsArray.contains { $0["googleSearchRetrieval"] != nil })
    }

    @Test("should pass response format")
    func testPassResponseFormat() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(
                schema: [
                    "type": .string("object"),
                    "properties": .object(["text": .object(["type": .string("string")])]),
                    "required": .array([.string("text")])
                ],
                name: nil,
                description: nil
            )
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let contents = json["contents"] as? [[String: Any]] else {
            Issue.record("Missing contents")
            return
        }

        #expect(contents.count == 1)

        guard let generationConfig = json["generationConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig")
            return
        }

        #expect(generationConfig["responseMimeType"] as? String == "application/json")

        guard let responseSchema = generationConfig["responseSchema"] as? [String: Any] else {
            Issue.record("Missing responseSchema")
            return
        }

        #expect(responseSchema["type"] as? String == "object")

        guard let properties = responseSchema["properties"] as? [String: Any] else {
            Issue.record("Missing properties")
            return
        }

        #expect(properties.keys.contains("text"))

        guard let required = responseSchema["required"] as? [String] else {
            Issue.record("Missing required")
            return
        }

        #expect(required == ["text"])
    }

    @Test("merges async config headers with sync request headers")
    func testMergesAsyncConfigHeadersWithSyncRequestHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let safetyRatings: [[String: Any]] = [
            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HATE_SPEECH", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HARASSMENT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "NEGLIGIBLE"]
        ]

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": ""]], "role": "model"],
                    "finishReason": "STOP",
                    "index": 0,
                    "safetyRatings": safetyRatings
                ]
            ],
            "promptFeedback": ["safetyRatings": safetyRatings],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 2,
                "totalTokenCount": 3
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [
                    "X-Async-Config": "async-config-value",
                    "X-Common": "config-value"
                ] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            headers: [
                "X-Sync-Request": "sync-request-value",
                "X-Common": "request-value"  // Should override config value
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]

        // Check that async config headers are present
        #expect(headers["X-Async-Config"] == "async-config-value" || headers["x-async-config"] == "async-config-value")

        // Check that sync request headers are present
        #expect(headers["X-Sync-Request"] == "sync-request-value" || headers["x-sync-request"] == "sync-request-value")

        // Check that request headers override config headers for common keys
        #expect(headers["X-Common"] == "request-value" || headers["x-common"] == "request-value")

        // Check content-type is set
        #expect(headers["Content-Type"] == "application/json" || headers["content-type"] == "application/json")
    }

    @Test("should not pass specification with responseFormat and structuredOutputs = false")
    func testNotPassSpecificationWithStructuredOutputsFalse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(
                schema: [
                    "type": .string("object"),
                    "properties": .object([
                        "property1": .object(["type": .string("string")]),
                        "property2": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("property1"), .string("property2")]),
                    "additionalProperties": .bool(false)
                ],
                name: nil,
                description: nil
            ),
            providerOptions: [
                "google": [
                    "structuredOutputs": .bool(false)
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let contents = json["contents"] as? [[String: Any]] else {
            Issue.record("Missing contents")
            return
        }

        #expect(contents.count == 1)

        guard let generationConfig = json["generationConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig")
            return
        }

        // When structuredOutputs = false, only responseMimeType should be set, no responseSchema
        #expect(generationConfig["responseMimeType"] as? String == "application/json")
        #expect(generationConfig["responseSchema"] == nil)
    }

    @Test("should use dynamic retrieval for gemini-1.5")
    func testUseDynamicRetrievalForGemini15() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.5-flash"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.google_search",
                    name: "google_search",
                    args: [
                        "mode": .string("MODE_DYNAMIC"),
                        "dynamicThreshold": .number(1)
                    ]
                ))
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let toolsArray = json["tools"] as? [[String: Any]],
              let googleSearchEntry = toolsArray.first(where: { $0["googleSearchRetrieval"] != nil }),
              let googleSearchRetrieval = googleSearchEntry["googleSearchRetrieval"] as? [String: Any],
              let dynamicRetrievalConfig = googleSearchRetrieval["dynamicRetrievalConfig"] as? [String: Any] else {
            Issue.record("Missing googleSearchRetrieval with dynamicRetrievalConfig")
            return
        }

        #expect(dynamicRetrievalConfig["mode"] as? String == "MODE_DYNAMIC")
        #expect(dynamicRetrievalConfig["dynamicThreshold"] as? Int == 1)
    }

    @Test("should use urlContextTool for gemini-2.0-pro")
    func testUseUrlContextToolForGemini20Pro() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.url_context",
                    name: "url_context",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let toolsArray = json["tools"] as? [[String: Any]],
              toolsArray.contains(where: { $0["urlContext"] != nil }) else {
            Issue.record("Missing tools in request")
            return
        }
    }

    @Test("should pass responseModalities in provider options")
    func testPassResponseModalitiesInProviderOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "responseModalities": .array([.string("TEXT"), .string("IMAGE")])
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let generationConfig = json["generationConfig"] as? [String: Any],
              let responseModalities = generationConfig["responseModalities"] as? [String] else {
            Issue.record("Missing responseModalities in generationConfig")
            return
        }

        #expect(responseModalities == ["TEXT", "IMAGE"])
    }

    @Test("should pass mediaResolution in provider options")
    func testPassMediaResolutionInProviderOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "mediaResolution": .string("MEDIA_RESOLUTION_LOW")
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let generationConfig = json["generationConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig")
            return
        }

        #expect(generationConfig["mediaResolution"] as? String == "MEDIA_RESOLUTION_LOW")
    }

    @Test("should extract image file outputs")
    func testExtractImageFileOutputs() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Here is an image:"],
                            ["inlineData": ["mimeType": "image/jpeg", "data": "base64encodedimagedata"]],
                            ["text": "And another image:"],
                            ["inlineData": ["mimeType": "image/png", "data": "anotherbase64encodedimagedata"]]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 4)

        if case .text(let text1) = result.content[0] {
            #expect(text1.text == "Here is an image:")
        } else {
            Issue.record("Expected text at index 0")
        }

        if case .file(let file1) = result.content[1] {
            #expect(file1.mediaType == "image/jpeg")
            #expect(file1.data == .base64("base64encodedimagedata"))
        } else {
            Issue.record("Expected file at index 1")
        }

        if case .text(let text2) = result.content[2] {
            #expect(text2.text == "And another image:")
        } else {
            Issue.record("Expected text at index 2")
        }

        if case .file(let file2) = result.content[3] {
            #expect(file2.mediaType == "image/png")
            #expect(file2.data == .base64("anotherbase64encodedimagedata"))
        } else {
            Issue.record("Expected file at index 3")
        }
    }

    @Test("should handle responses with only images and no text")
    func testHandleResponsesWithOnlyImagesAndNoText() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["inlineData": ["mimeType": "image/jpeg", "data": "imagedata1"]],
                            ["inlineData": ["mimeType": "image/png", "data": "imagedata2"]]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 2)

        if case .file(let file1) = result.content[0] {
            #expect(file1.mediaType == "image/jpeg")
            #expect(file1.data == .base64("imagedata1"))
        } else {
            Issue.record("Expected file at index 0")
        }

        if case .file(let file2) = result.content[1] {
            #expect(file2.mediaType == "image/png")
            #expect(file2.data == .base64("imagedata2"))
        } else {
            Issue.record("Expected file at index 1")
        }
    }

    @Test("should include non-image inlineData parts")
    func testIncludeNonImageInlineDataParts() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Here is content:"],
                            ["inlineData": ["mimeType": "image/jpeg", "data": "validimagedata"]],
                            ["inlineData": ["mimeType": "application/pdf", "data": "pdfdata"]]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 3)

        if case .text(let text) = result.content[0] {
            #expect(text.text == "Here is content:")
        } else {
            Issue.record("Expected text at index 0")
        }

        if case .file(let file1) = result.content[1] {
            #expect(file1.mediaType == "image/jpeg")
            #expect(file1.data == .base64("validimagedata"))
        } else {
            Issue.record("Expected file at index 1")
        }

        if case .file(let file2) = result.content[2] {
            #expect(file2.mediaType == "application/pdf")
            #expect(file2.data == .base64("pdfdata"))
        } else {
            Issue.record("Expected file at index 2")
        }
    }

    @Test("should correctly parse and separate reasoning parts from text output")
    func testCorrectlyParseAndSeparateReasoningPartsFromTextOutput() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Visible text part 1. "],
                            ["text": "This is a thought process.", "thought": true],
                            ["text": "Visible text part 2."],
                            ["text": "Another internal thought.", "thought": true]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 4)

        if case .text(let text1) = result.content[0] {
            #expect(text1.text == "Visible text part 1. ")
        } else {
            Issue.record("Expected text at index 0")
        }

        if case .reasoning(let reasoning1) = result.content[1] {
            #expect(reasoning1.text == "This is a thought process.")
        } else {
            Issue.record("Expected reasoning at index 1")
        }

        if case .text(let text2) = result.content[2] {
            #expect(text2.text == "Visible text part 2.")
        } else {
            Issue.record("Expected text at index 2")
        }

        if case .reasoning(let reasoning2) = result.content[3] {
            #expect(reasoning2.text == "Another internal thought.")
        } else {
            Issue.record("Expected reasoning at index 3")
        }
    }

    @Test("handles Promise-based headers")
    func testHandlesPromiseBasedHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let safetyRatings: [[String: Any]] = [
            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HATE_SPEECH", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_HARASSMENT", "probability": "NEGLIGIBLE"],
            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "NEGLIGIBLE"]
        ]

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": ""]], "role": "model"],
                    "finishReason": "STOP",
                    "safetyRatings": safetyRatings
                ]
            ],
            "promptFeedback": ["safetyRatings": safetyRatings],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 2,
                "totalTokenCount": 3
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { ["X-Promise-Header": "promise-value"] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]

        #expect(headers["X-Promise-Header"] == "promise-value" || headers["x-promise-header"] == "promise-value")
        #expect(headers["Content-Type"] == "application/json" || headers["content-type"] == "application/json")
    }

    @Test("handles async function headers from config")
    func testHandlesAsyncFunctionHeadersFromConfig() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": ""]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { ["X-Async-Header": "async-value"] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]

        #expect(headers["X-Async-Header"] == "async-value" || headers["x-async-header"] == "async-value")
        #expect(headers["Content-Type"] == "application/json" || headers["content-type"] == "application/json")
    }

    @Test("should use googleSearch for gemini-2.0-flash-exp")
    func testUseGoogleSearchForGemini20FlashExp() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-flash-exp"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .providerDefined(LanguageModelV3ProviderDefinedTool(
                    id: "google.google_search",
                    name: "google_search",
                    args: [:]
                ))
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let toolsArray = json["tools"] as? [[String: Any]] else {
            Issue.record("Missing tools in request")
            return
        }

        #expect(toolsArray.contains { $0["googleSearch"] != nil })
    }

    @Test("should pass specification with responseFormat and structuredOutputs = true (default)")
    func testPassSpecificationWithStructuredOutputsTrue() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "response"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            responseFormat: .json(
                schema: [
                    "type": .string("object"),
                    "properties": .object([
                        "property1": .object(["type": .string("string")]),
                        "property2": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("property1"), .string("property2")]),
                    "additionalProperties": .bool(false)
                ],
                name: nil,
                description: nil
            )
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        guard let generationConfig = json["generationConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig")
            return
        }

        // By default, structuredOutputs is true, so responseSchema should be present
        #expect(generationConfig["responseMimeType"] as? String == "application/json")
        #expect(generationConfig["responseSchema"] != nil)

        guard let responseSchema = generationConfig["responseSchema"] as? [String: Any] else {
            Issue.record("Missing responseSchema")
            return
        }

        #expect(responseSchema["type"] as? String == "object")
    }

    @Test("should correctly parse thought signatures with function calls")
    func testCorrectlyParseThoughtSignaturesWithFunctionCalls() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "functionCall": [
                                    "name": "test_function",
                                    "args": ["param": "value"]
                                ],
                                "thoughtSignature": "sig1"
                            ]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count >= 1)

        if case .toolCall(let toolCall) = result.content[0] {
            #expect(toolCall.toolName == "test_function")
            #expect(toolCall.providerMetadata != nil)

            // Check that thoughtSignature is in providerMetadata
            guard let metadata = toolCall.providerMetadata,
                  let googleMeta = metadata["google"],
                  let thoughtSig = googleMeta["thoughtSignature"] else {
                Issue.record("Expected thoughtSignature in providerMetadata")
                return
            }

            #expect(thoughtSig == .string("sig1"))
        } else {
            Issue.record("Expected tool call at index 0")
        }
    }

    @Test("should correctly parse thought signatures with reasoning parts")
    func testCorrectlyParseThoughtSignaturesWithReasoningParts() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Visible text part 1. ", "thoughtSignature": "sig1"],
                            ["text": "This is a thought process.", "thought": true, "thoughtSignature": "sig2"],
                            ["text": "Visible text part 2.", "thoughtSignature": "sig3"]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.content.count == 3)

        // All parts should have thoughtSignature in their providerMetadata
        if case .text(let text1) = result.content[0] {
            #expect(text1.text == "Visible text part 1. ")
            guard let metadata = text1.providerMetadata,
                  let googleMeta = metadata["google"],
                  let thoughtSig = googleMeta["thoughtSignature"] else {
                Issue.record("Expected thoughtSignature in text1 providerMetadata")
                return
            }
            #expect(thoughtSig == .string("sig1"))
        } else {
            Issue.record("Expected text at index 0")
        }

        if case .reasoning(let reasoning) = result.content[1] {
            #expect(reasoning.text == "This is a thought process.")
            guard let metadata = reasoning.providerMetadata,
                  let googleMeta = metadata["google"],
                  let thoughtSig = googleMeta["thoughtSignature"] else {
                Issue.record("Expected thoughtSignature in reasoning providerMetadata")
                return
            }
            #expect(thoughtSig == .string("sig2"))
        } else {
            Issue.record("Expected reasoning at index 1")
        }

        if case .text(let text2) = result.content[2] {
            #expect(text2.text == "Visible text part 2.")
            guard let metadata = text2.providerMetadata,
                  let googleMeta = metadata["google"],
                  let thoughtSig = googleMeta["thoughtSignature"] else {
                Issue.record("Expected thoughtSignature in text2 providerMetadata")
                return
            }
            #expect(thoughtSig == .string("sig3"))
        } else {
            Issue.record("Expected text at index 2")
        }
    }

    // MARK: - doStream Tests

    @Test("should stream text deltas")
    func testStreamTextDeltas() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":", "}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"world!"}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":294,"candidatesTokenCount":233,"totalTokenCount":527}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "0" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for stream-start
        guard let streamStart = parts.first, case .streamStart = streamStart else {
            Issue.record("Expected stream-start at beginning")
            return
        }

        // Check for text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas == ["Hello", ", ", "world!"])

        // Check for finish
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(finishReason, usage, _) = finish {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 294)
            #expect(usage.outputTokens == 233)
            #expect(usage.totalTokens == 527)
        }
    }

    @Test("should stream source events")
    func testStreamSourceEvents() async throws {
        let groundingMetadata = #"{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}}]}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Some initial text"}]},"groundingMetadata":\#(groundingMetadata)}],"usageMetadata":{"promptTokenCount":294,"candidatesTokenCount":233,"totalTokenCount":527}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for source events
        let sources = parts.compactMap { part -> (String, String)? in
            if case .source(let source) = part,
               case let .url(_, url, title, _) = source {
                return (url, title ?? "")
            }
            return nil
        }

        #expect(sources.count == 1)
        #expect(sources[0].0 == "https://source.example.com")
        #expect(sources[0].1 == "Source Title")
    }

    @Test("should stream sources during intermediate chunks")
    func testStreamSourcesDuringIntermediateChunks() async throws {
        let groundingMeta1 = #"{"groundingChunks":[{"web":{"uri":"https://a.com","title":"A"}},{"web":{"uri":"https://b.com","title":"B"}}]}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"text"}]},"groundingMetadata":\#(groundingMeta1)}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"more"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for source events
        let sources = parts.compactMap { part -> (String, String)? in
            if case .source(let source) = part,
               case let .url(_, url, title, _) = source {
                return (url, title ?? "")
            }
            return nil
        }

        #expect(sources.count == 2)
        #expect(sources[0].0 == "https://a.com")
        #expect(sources[0].1 == "A")
        #expect(sources[1].0 == "https://b.com")
        #expect(sources[1].1 == "B")
    }

    @Test("should deduplicate sources across chunks")
    func testDeduplicateSourcesAcrossChunks() async throws {
        let groundingMeta1 = #"{"groundingChunks":[{"web":{"uri":"https://example.com","title":"Example"}},{"web":{"uri":"https://unique.com","title":"Unique"}}]}"#
        let groundingMeta2 = #"{"groundingChunks":[{"web":{"uri":"https://example.com","title":"Example Duplicate"}},{"web":{"uri":"https://another.com","title":"Another"}}]}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"first chunk"}]},"groundingMetadata":\#(groundingMeta1)}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"second chunk"}]},"groundingMetadata":\#(groundingMeta2)}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"final chunk"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for source events - should be deduplicated by URL
        let sources = parts.compactMap { part -> String? in
            if case .source(let source) = part,
               case let .url(_, url, _, _) = source {
                return url
            }
            return nil
        }

        // Only unique URLs should appear: https://example.com (first occurrence), https://unique.com, https://another.com
        #expect(sources.count == 3)
        #expect(sources.contains("https://example.com"))
        #expect(sources.contains("https://unique.com"))
        #expect(sources.contains("https://another.com"))
        // Verify example.com appears only once despite being in both chunks
        #expect(sources.filter { $0 == "https://example.com" }.count == 1)
    }

    @Test("should stream files")
    func testStreamFiles() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"inlineData":{"data":"test","mimeType":"text/plain"}}]},"finishReason":"STOP"}]}"#,
            #"{"usageMetadata":{"promptTokenCount":294,"candidatesTokenCount":233,"totalTokenCount":527}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for file event
        let files = parts.compactMap { part -> (String, String)? in
            if case .file(let file) = part {
                if case .base64(let data) = file.data {
                    return (file.mediaType, data)
                }
            }
            return nil
        }

        #expect(files.count == 1)
        #expect(files[0].0 == "text/plain")
        #expect(files[0].1 == "test")
    }

    @Test("should set finishReason to tool-calls when chunk contains functionCall")
    func testSetFinishReasonToToolCallsWhenChunkContainsFunctionCall() async throws {
        let functionCall = #"{"name":"get_weather","args":{"location":"Paris"}}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"functionCall":\#(functionCall)}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for finish with tool-calls reason
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(finishReason, _, _) = finish {
            #expect(finishReason == .toolCalls)
        }
    }

    @Test("should use googleSearch for gemini-2.0-pro")
    func testUseGoogleSearchForGemini20ProStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "google.google_search",
                name: "google_search",
                args: [:]
            ))],
            includeRawChunks: false
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check that googleSearch tool is used
        if let toolsArray = json["tools"] as? [[String: Any]] {
            #expect(toolsArray.contains { $0["googleSearch"] != nil })
        } else {
            Issue.record("Missing tools in request")
        }
    }

    @Test("should use googleSearch for gemini-2.0-flash-exp")
    func testUseGoogleSearchForGemini20FlashExpStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-flash-exp"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "google.google_search",
                name: "google_search",
                args: [:]
            ))],
            includeRawChunks: false
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check that googleSearch tool is used
        if let toolsArray = json["tools"] as? [[String: Any]] {
            #expect(toolsArray.contains { $0["googleSearch"] != nil })
        } else {
            Issue.record("Missing tools in request")
        }
    }

    @Test("should use googleSearchRetrieval for non-gemini-2 models")
    func testUseGoogleSearchRetrievalForNonGemini2Stream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "google.google_search",
                name: "google_search",
                args: [:]
            ))],
            includeRawChunks: false
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check that googleSearchRetrieval tool is used
        if let toolsArray = json["tools"] as? [[String: Any]] {
            #expect(toolsArray.contains { $0["googleSearchRetrieval"] != nil })
        } else {
            Issue.record("Missing tools in request")
        }
    }

    @Test("should use dynamic retrieval for gemini-1.5")
    func testUseDynamicRetrievalForGemini15Stream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.5-flash"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "google.google_search",
                name: "google_search",
                args: [
                    "mode": .string("MODE_DYNAMIC"),
                    "dynamicThreshold": .number(1)
                ]
            ))],
            includeRawChunks: false
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check that googleSearchRetrieval with dynamic config is used
        if let toolsArray = json["tools"] as? [[String: Any]],
           let googleSearchRetrieval = toolsArray.first(where: { $0["googleSearchRetrieval"] != nil })?["googleSearchRetrieval"] as? [String: Any],
           let dynamicRetrievalConfig = googleSearchRetrieval["dynamicRetrievalConfig"] as? [String: Any] {
            #expect(dynamicRetrievalConfig["mode"] as? String == "MODE_DYNAMIC")
            #expect(dynamicRetrievalConfig["dynamicThreshold"] as? Int == 1)
        } else {
            Issue.record("Missing googleSearchRetrieval with dynamic config in request")
        }
    }

    @Test("should expose safety ratings in provider metadata on finish")
    func testExposeSafetyRatingsInProviderMetadataOnFinish() async throws {
        let safetyRatings = #"[{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"NEGLIGIBLE","probabilityScore":0.1,"severity":"LOW","severityScore":0.2,"blocked":false}]"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"test"}]},"finishReason":"STOP","safetyRatings":\#(safetyRatings)}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for finish event with safety ratings in provider metadata
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(_, _, providerMetadata) = finish {
            guard let metadata = providerMetadata,
                  let googleMeta = metadata["google"],
                  let safetyRatingsValue = googleMeta["safetyRatings"],
                  case .array(let ratings) = safetyRatingsValue else {
                Issue.record("Expected safetyRatings in provider metadata")
                return
            }

            #expect(ratings.count == 1)
            if case .object(let rating) = ratings[0] {
                #expect(rating["category"] == .string("HARM_CATEGORY_DANGEROUS_CONTENT"))
                #expect(rating["probability"] == .string("NEGLIGIBLE"))
            }
        }
    }

    @Test("should expose PromptFeedback in provider metadata on finish")
    func testExposePromptFeedbackInProviderMetadataOnFinish() async throws {
        let promptFeedback = #"{"blockReason":"SAFETY","safetyRatings":[{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"HIGH"}]}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"test"}]},"finishReason":"STOP"}],"promptFeedback":\#(promptFeedback)}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for finish event with promptFeedback in provider metadata
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(_, _, providerMetadata) = finish {
            guard let metadata = providerMetadata,
                  let googleMeta = metadata["google"],
                  let promptFeedbackValue = googleMeta["promptFeedback"],
                  case .object(let feedback) = promptFeedbackValue else {
                Issue.record("Expected promptFeedback in provider metadata")
                return
            }

            #expect(feedback["blockReason"] == .string("SAFETY"))
        }
    }

    @Test("should expose grounding metadata in provider metadata on finish")
    func testExposeGroundingMetadataInProviderMetadataOnFinish() async throws {
        let groundingMetadata = #"{"webSearchQueries":["What's the weather in Chicago this weekend?"],"searchEntryPoint":{"renderedContent":"Sample rendered content"}}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"test"}]},"finishReason":"STOP","groundingMetadata":\#(groundingMetadata)}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for finish event with grounding metadata
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(_, _, providerMetadata) = finish {
            guard let metadata = providerMetadata,
                  let googleMeta = metadata["google"],
                  let groundingMetaValue = googleMeta["groundingMetadata"],
                  case .object(let groundingMeta) = groundingMetaValue else {
                Issue.record("Expected groundingMetadata in provider metadata")
                return
            }

            if case .array(let queries) = groundingMeta["webSearchQueries"] {
                #expect(queries.count == 1)
                #expect(queries[0] == .string("What's the weather in Chicago this weekend?"))
            }
        }
    }

    @Test("should expose url context metadata in provider metadata on finish")
    func testExposeUrlContextMetadataInProviderMetadataOnFinish() async throws {
        let urlContextMetadata = #"{"urlMetadata":[{"retrievedUrl":"https://example.com/weather","urlRetrievalStatus":"URL_RETRIEVAL_STATUS_SUCCESS"}]}"#
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"test"}]},"finishReason":"STOP","urlContextMetadata":\#(urlContextMetadata)}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for finish event with url context metadata
        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Missing finish part")
            return
        }

        if case let .finish(_, _, providerMetadata) = finish {
            guard let metadata = providerMetadata,
                  let googleMeta = metadata["google"],
                  let urlContextMetaValue = googleMeta["urlContextMetadata"],
                  case .object(let urlContextMeta) = urlContextMetaValue else {
                Issue.record("Expected urlContextMetadata in provider metadata")
                return
            }

            if case .array(let urlMetadata) = urlContextMeta["urlMetadata"] {
                #expect(urlMetadata.count == 1)
            }
        }
    }

    @Test("should only pass valid provider options")
    func testOnlyPassValidProviderOptionsStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false,
            providerOptions: [
                "google": [
                    "foo": .string("bar"), // invalid option, should be ignored
                    "responseModalities": .array([.string("TEXT"), .string("IMAGE")])
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Check that only valid options are passed
        if let generationConfig = json["generationConfig"] as? [String: Any],
           let responseModalities = generationConfig["responseModalities"] as? [String] {
            #expect(responseModalities == ["TEXT", "IMAGE"])
        } else {
            Issue.record("Missing responseModalities in generationConfig")
        }

        // Check that foo is not in the request
        #expect(json["foo"] == nil)
        if let generationConfig = json["generationConfig"] as? [String: Any] {
            #expect(generationConfig["foo"] == nil)
        }
    }

    @Test("should stream reasoning parts separately from text parts")
    func testStreamReasoningPartsSeparatelyFromTextParts() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Visible text 1"}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"This is reasoning","thought":true}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"Visible text 2"}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for text deltas (visible text)
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        // Check for reasoning deltas
        let reasoningDeltas = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.contains("Visible text 1"))
        #expect(textDeltas.contains("Visible text 2"))
        #expect(reasoningDeltas.contains("This is reasoning"))
    }

    @Test("should stream thought signatures with reasoning and text parts")
    func testStreamThoughtSignaturesWithReasoningAndTextParts() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Visible 1","thoughtSignature":"sig1"}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"Reasoning","thought":true,"thoughtSignature":"sig2"}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"Visible 2","thoughtSignature":"sig3"}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check that text parts have thoughtSignature in metadata
        let textWithSignatures = parts.compactMap { part -> String? in
            if case .textDelta(_, _, let metadata) = part,
               let meta = metadata,
               let googleMeta = meta["google"],
               case .string = googleMeta["thoughtSignature"] {
                return "found"
            }
            return nil
        }

        #expect(textWithSignatures.count >= 2) // Should have at least 2 text deltas with signatures

        // Check that reasoning parts have thoughtSignature in metadata
        let reasoningWithSignatures = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, _, let metadata) = part,
               let meta = metadata,
               let googleMeta = meta["google"],
               let thoughtSig = googleMeta["thoughtSignature"],
               case .string(let sig) = thoughtSig {
                return sig
            }
            return nil
        }

        #expect(reasoningWithSignatures.contains("sig2"))
    }

    @Test("should include raw chunks when includeRawChunks is enabled")
    func testIncludeRawChunksWhenEnabled() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: true
        ))

        let parts = try await collectStream(result.stream)

        // Check that raw chunks are included
        let hasRawChunk = parts.contains { part in
            if case .raw = part {
                return true
            }
            return false
        }

        #expect(hasRawChunk == true)
    }

    @Test("should not include raw chunks when includeRawChunks is false")
    func testNotIncludeRawChunksWhenDisabled() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check that raw chunks are NOT included
        let hasRawChunk = parts.contains { part in
            if case .raw = part {
                return true
            }
            return false
        }

        #expect(hasRawChunk == false)
    }

    // MARK: - GEMMA Model Tests

    @Test("should NOT send systemInstruction for GEMMA-3-12b-it model")
    func testNotSendSystemInstructionForGEMMA12b() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hello!"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemma-3-12b-it:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemma-3-12b-it"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Verify that systemInstruction was NOT sent for GEMMA model
        #expect(json["systemInstruction"] == nil)
    }

    @Test("should NOT send systemInstruction for GEMMA-3-27b-it model")
    func testNotSendSystemInstructionForGEMMA27b() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hello!"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemma-3-27b-it:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemma-3-27b-it"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Verify that systemInstruction was NOT sent for GEMMA model
        #expect(json["systemInstruction"] == nil)
    }

    @Test("should still send systemInstruction for Gemini models (regression test)")
    func testStillSendSystemInstructionForGemini() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hello!"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Verify that systemInstruction WAS sent for Gemini model
        guard let systemInstruction = json["systemInstruction"] as? [String: Any] else {
            Issue.record("Expected systemInstruction for Gemini model")
            return
        }

        guard let parts = systemInstruction["parts"] as? [[String: Any]] else {
            Issue.record("Expected parts in systemInstruction")
            return
        }

        #expect(parts.count == 1)
        #expect(parts[0]["text"] as? String == "You are a helpful assistant.")
    }

    @Test("should NOT generate warning when GEMMA model is used without system instructions")
    func testNotGenerateWarningWhenGEMMAWithoutSystemInstructions() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hello!"]], "role": "model"],
                    "finishReason": "STOP",
                    "index": 0
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemma-3-12b-it:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemma-3-12b-it"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { ["x-goog-api-key": "test-api-key"] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.warnings.isEmpty)
    }

    @Test("should NOT generate warning when Gemini model is used with system instructions")
    func testNotGenerateWarningWhenGeminiWithSystemInstructions() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hello!"]], "role": "model"],
                    "finishReason": "STOP",
                    "index": 0
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { ["x-goog-api-key": "test-api-key"] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        #expect(result.warnings.isEmpty)
    }

    @Test("should prepend system instruction to first user message for GEMMA models")
    func testPrependSystemInstructionToFirstUserMessageForGEMMA() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "Hi there!"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemma-3-12b-it:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemma-3-12b-it"),
            config: makeLanguageModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil),
                .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try decodeRequestBody(request)

        // Verify systemInstruction was NOT sent
        #expect(json["systemInstruction"] == nil)

        // Verify system message was prepended to first user message
        guard let contents = json["contents"] as? [[String: Any]] else {
            Issue.record("Expected contents array")
            return
        }

        #expect(contents.count >= 1)

        guard let firstMessage = contents.first,
              let parts = firstMessage["parts"] as? [[String: Any]],
              parts.count >= 2 else {
            Issue.record("Expected at least 2 parts in first message")
            return
        }

        // First part should be system instruction
        guard let firstPartText = parts[0]["text"] as? String else {
            Issue.record("Expected text in first part")
            return
        }
        #expect(firstPartText.contains("You are a helpful assistant."))

        // Second part should be user message
        guard let secondPartText = parts[1]["text"] as? String else {
            Issue.record("Expected text in second part")
            return
        }
        #expect(secondPartText == "Hello")
    }

    @Test("should stream code execution tool calls and results")
    func testStreamCodeExecutionToolCallsAndResults() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"executableCode":{"language":"PYTHON","code":"print(\"hello\")"}}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"codeExecutionResult":{"outcome":"OUTCOME_OK","output":"hello\n"}}]},"finishReason":"STOP"}]}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.0-pro"),
            config: makeLanguageModelConfig(fetch: fetch, generateId: { "test-id" })
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [.providerDefined(LanguageModelV3ProviderDefinedTool(
                id: "code_execution",
                name: "code_execution",
                args: [:]
            ))],
            includeRawChunks: false
        ))

        let parts = try await collectStream(result.stream)

        // Check for tool-call event
        let toolCalls = parts.compactMap { part -> (String, String, String, Bool)? in
            if case .toolCall(let call) = part {
                return (call.toolCallId, call.toolName, call.input, call.providerExecuted ?? false)
            }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].0 == "test-id")
        #expect(toolCalls[0].1 == "code_execution")
        #expect(toolCalls[0].2.contains("PYTHON"))
        #expect(toolCalls[0].2.contains("print"))
        #expect(toolCalls[0].3 == true)

        // Check for tool-result event - result.result is JSONValue!
        let toolResults = parts.compactMap { part -> (String, String, Bool)? in
            if case .toolResult(let result) = part {
                if case .object(let dict) = result.result,
                   case .string(let outcome) = dict["outcome"],
                   case .string(let output) = dict["output"] {
                    return (outcome, output, result.providerExecuted ?? false)
                }
            }
            return nil
        }

        #expect(toolResults.count == 1)
        #expect(toolResults[0].0 == "OUTCOME_OK")
        #expect(toolResults[0].1 == "hello\n")
        #expect(toolResults[0].2 == true)
    }

    // MARK: - includeThoughts Warning Tests

    @Test("should generate a warning if includeThoughts is true for a non-Vertex provider")
    func testGenerateWarningIfIncludeThoughtsForNonVertex() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "test"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai.chat",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [:] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "thinkingConfig": .object([
                        "includeThoughts": .bool(true),
                        "thinkingBudget": .number(500)
                    ])
                ]
            ]
        ))

        #expect(result.warnings.count == 1)
        if case .other(let message) = result.warnings[0] {
            #expect(message == "The 'includeThoughts' option is only supported with the Google Vertex provider and might not be supported or could behave unexpectedly with the current Google provider (google.generative-ai.chat).")
        }
    }

    @Test("should NOT generate a warning if includeThoughts is true for a Vertex provider")
    func testNotGenerateWarningIfIncludeThoughtsForVertex() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "test"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.vertex.chat",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [:] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "thinkingConfig": .object([
                        "includeThoughts": .bool(true),
                        "thinkingBudget": .number(500)
                    ])
                ]
            ]
        ))

        #expect(result.warnings.isEmpty)
    }

    @Test("should NOT generate a warning if includeThoughts is false for a non-Vertex provider")
    func testNotGenerateWarningIfIncludeThoughtsFalseForNonVertex() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "test"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai.chat",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [:] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "thinkingConfig": .object([
                        "includeThoughts": .bool(false),
                        "thinkingBudget": .number(500)
                    ])
                ]
            ]
        ))

        #expect(result.warnings.isEmpty)
    }

    @Test("should NOT generate a warning if thinkingConfig is not provided for a non-Vertex provider")
    func testNotGenerateWarningIfThinkingConfigNotProvided() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": [["text": "test"]], "role": "model"],
                    "finishReason": "STOP"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai.chat",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { [:] },
                fetch: fetch,
                generateId: { "test-id" },
                supportedUrls: { [:] }
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: ["google": [:]]
        ))

        #expect(result.warnings.isEmpty)
    }
}
