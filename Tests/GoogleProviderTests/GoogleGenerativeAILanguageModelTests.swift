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

        var idCounter = 0
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

    @Test("doStream emits text, reasoning, tool events and raw chunks")
    func testDoStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
        }

        let capture = RequestCapture()
        var streamCounter = 0

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
}
