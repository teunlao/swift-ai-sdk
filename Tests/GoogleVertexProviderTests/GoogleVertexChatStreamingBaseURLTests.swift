import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexProvider (chat streaming baseURL)")
struct GoogleVertexChatStreamingBaseURLTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?

        func set(_ request: URLRequest) {
            lastRequest = request
        }
    }

    private func headerValue(_ name: String, in request: URLRequest) -> String? {
        request.allHTTPHeaderFields?.first(where: { $0.key.lowercased() == name.lowercased() })?.value
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

    private func makePrompt() -> LanguageModelV3Prompt {
        [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
    }

    @Test("uses regional streamGenerateContent URL when apiKey is not provided")
    func usesRegionalStreamURL_whenNotExpress() async throws {
        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.set(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            ))
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        let result = try await model.doStream(options: .init(prompt: makePrompt()))
        _ = try await collectStream(result.stream)

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/gemini-pro:streamGenerateContent?alt=sse")
        #expect(headerValue("x-goog-api-key", in: request) == nil)
    }

    @Test("uses express streamGenerateContent URL and injects x-goog-api-key when apiKey is provided")
    func usesExpressStreamURL_andInjectsApiKey() async throws {
        let capture = RequestCapture()

        let payloads = [
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}"#
        ]
        let events = sseEvents(from: payloads)

        let fetch: FetchFunction = { request in
            await capture.set(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            ))
            return FetchResponse(body: .stream(makeSSEStream(from: events)), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "KEY",
            fetch: fetch
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        let result = try await model.doStream(options: .init(prompt: makePrompt()))
        _ = try await collectStream(result.stream)

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-pro:streamGenerateContent?alt=sse")
        #expect(headerValue("x-goog-api-key", in: request) == "KEY")
    }
}

