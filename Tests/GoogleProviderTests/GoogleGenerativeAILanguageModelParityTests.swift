import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

private func makeParityModelConfig(
    provider: String = "google.generative-ai",
    fetch: @escaping FetchFunction,
    generateId: @escaping @Sendable () -> String = { "test-id" }
) -> GoogleGenerativeAILanguageModel.Config {
    GoogleGenerativeAILanguageModel.Config(
        provider: provider,
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        headers: { ["x-goog-api-key": "test"] },
        fetch: fetch,
        generateId: generateId,
        supportedUrls: { [:] }
    )
}

private func decodeParityRequestBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody else {
        throw NSError(domain: "ParityTests", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing body"])
    }
    return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
}

private func makeParitySSEStream(from events: [String]) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data(event.utf8))
        }
        continuation.finish()
    }
}

private func paritySSEEvents(from payloads: [String], appendDone: Bool = true) -> [String] {
    var events = payloads.map { "data: \($0)\n\n" }
    if appendDone {
        events.append("data: [DONE]\n\n")
    }
    return events
}

private func collectParityStream(
    _ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
) async throws -> [LanguageModelV3StreamPart] {
    var parts: [LanguageModelV3StreamPart] = []
    for try await part in stream {
        parts.append(part)
    }
    return parts
}

@Suite("GoogleGenerativeAILanguageModel Parity")
struct GoogleGenerativeAILanguageModelParityTests {
    @Test("passes imageConfig.imageSize in generation config")
    func passesImageConfigImageSize() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": "ok"]], "role": "model"],
                "finishReason": "STOP"
            ]]
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
            config: makeParityModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "imageConfig": .object([
                        "imageSize": .string("4K")
                    ])
                ]
            ]
        ))

        guard let request = await capture.value(),
              let generationConfig = try decodeParityRequestBody(request)["generationConfig"] as? [String: Any],
              let imageConfig = generationConfig["imageConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig.imageConfig")
            return
        }

        #expect(imageConfig["imageSize"] as? String == "4K")
    }

    @Test("passes thinkingConfig.thinkingLevel in generation config")
    func passesThinkingLevel() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": "ok"]], "role": "model"],
                "finishReason": "STOP"
            ]]
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
            config: makeParityModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "thinkingConfig": .object([
                        "thinkingLevel": .string("high")
                    ])
                ]
            ]
        ))

        guard let request = await capture.value(),
              let generationConfig = try decodeParityRequestBody(request)["generationConfig"] as? [String: Any],
              let thinkingConfig = generationConfig["thinkingConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig.thinkingConfig")
            return
        }

        #expect(thinkingConfig["thinkingLevel"] as? String == "high")
    }

    @Test("passes retrievalConfig in merged toolConfig")
    func passesRetrievalConfigInToolConfig() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": "ok"]], "role": "model"],
                "finishReason": "STOP"
            ]]
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
            config: makeParityModelConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            tools: [
                .provider(LanguageModelV3ProviderTool(
                    id: "google.google_maps",
                    name: "google_maps",
                    args: [:]
                ))
            ],
            providerOptions: [
                "google": [
                    "retrievalConfig": .object([
                        "latLng": .object([
                            "latitude": .number(34.090199),
                            "longitude": .number(-117.881081)
                        ])
                    ])
                ]
            ]
        ))

        guard let request = await capture.value(),
              let body = try decodeParityRequestBody(request)["toolConfig"] as? [String: Any],
              let retrievalConfig = body["retrievalConfig"] as? [String: Any],
              let latLng = retrievalConfig["latLng"] as? [String: Any] else {
            Issue.record("Missing toolConfig.retrievalConfig.latLng")
            return
        }

        #expect(latLng["latitude"] as? Double == 34.090199)
        #expect(latLng["longitude"] as? Double == -117.881081)
    }

    @Test("falls back to google provider options namespace for vertex provider")
    func fallsBackToGoogleProviderOptionsForVertex() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": "ok"]], "role": "model"],
                "finishReason": "STOP"
            ]]
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
            config: makeParityModelConfig(provider: "google.vertex.chat", fetch: fetch)
        )

        _ = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)],
            providerOptions: [
                "google": [
                    "thinkingConfig": .object([
                        "thinkingLevel": .string("medium")
                    ])
                ]
            ]
        ))

        guard let request = await capture.value(),
              let generationConfig = try decodeParityRequestBody(request)["generationConfig"] as? [String: Any],
              let thinkingConfig = generationConfig["thinkingConfig"] as? [String: Any] else {
            Issue.record("Missing generationConfig.thinkingConfig")
            return
        }

        #expect(thinkingConfig["thinkingLevel"] as? String == "medium")
    }

    @Test("uses vertex metadata key for generate response and thought signature metadata")
    func usesVertexMetadataKeyInGenerate() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        [
                            "text": "thinking...",
                            "thought": true,
                            "thoughtSignature": "sig-vertex"
                        ],
                        ["text": "Final answer"]
                    ],
                    "role": "model"
                ],
                "finishReason": "STOP",
                "safetyRatings": [["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT"]]
            ]],
            "promptFeedback": ["blocked": false],
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
            config: makeParityModelConfig(provider: "google.vertex.chat", fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        #expect(result.providerMetadata?["vertex"] != nil)
        #expect(result.providerMetadata?["google"] == nil)

        let reasoningPart = result.content.first { content in
            if case .reasoning = content { return true }
            return false
        }

        guard let reasoningPart,
              case let .reasoning(reasoning) = reasoningPart else {
            Issue.record("Expected reasoning part")
            return
        }

        #expect(reasoning.providerMetadata?["vertex"]?["thoughtSignature"] == .string("sig-vertex"))
        #expect(reasoning.providerMetadata?["google"] == nil)
    }

    @Test("uses vertex metadata key for stream finish and reasoning events")
    func usesVertexMetadataKeyInStream() async throws {
        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"thinking...","thought":true,"thoughtSignature":"stream-sig"}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"done"}]},"finishReason":"STOP","safetyRatings":[{"category":"HARM_CATEGORY_SEXUALLY_EXPLICIT"}]}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#
        ]
        let events = paritySSEEvents(from: payloads)

        let fetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return FetchResponse(body: .stream(makeParitySSEStream(from: events)), urlResponse: response)
        }

        let model = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro"),
            config: makeParityModelConfig(
                provider: "google.vertex.chat",
                fetch: fetch,
                generateId: { "stream-id" }
            )
        )

        let result = try await model.doStream(options: .init(
            prompt: [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]
        ))

        let parts = try await collectParityStream(result.stream)

        let reasoningDelta = parts.first { part in
            if case .reasoningDelta = part { return true }
            return false
        }

        guard let reasoningDelta,
              case let .reasoningDelta(_, _, providerMetadata) = reasoningDelta else {
            Issue.record("Expected reasoning-delta event")
            return
        }

        #expect(providerMetadata?["vertex"]?["thoughtSignature"] == .string("stream-sig"))
        #expect(providerMetadata?["google"] == nil)

        let finishPart = parts.first { part in
            if case .finish = part { return true }
            return false
        }

        guard let finishPart,
              case let .finish(_, _, providerMetadata) = finishPart else {
            Issue.record("Expected finish event")
            return
        }

        #expect(providerMetadata?["vertex"] != nil)
        #expect(providerMetadata?["google"] == nil)
    }
}
