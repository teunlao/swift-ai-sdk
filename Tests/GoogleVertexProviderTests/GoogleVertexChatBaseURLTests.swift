import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexProvider (chat baseURL)")
struct GoogleVertexChatBaseURLTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?

        func set(_ request: URLRequest) {
            lastRequest = request
        }
    }

    private func headerValue(_ name: String, in request: URLRequest) -> String? {
        request.allHTTPHeaderFields?.first(where: { $0.key.lowercased() == name.lowercased() })?.value
    }

    private func makeOKChatResponse(url: URL) throws -> FetchResponse {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "hello"]
                        ]
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json",
                "Content-Length": "\(data.count)"
            ]
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    private func makePrompt() -> LanguageModelV3Prompt {
        [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]
    }

    @Test("uses regional (location-prefixed) baseURL when apiKey is not provided")
    func usesRegionalBaseURL_whenNotExpress() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKChatResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        _ = try await model.doGenerate(options: .init(prompt: makePrompt()))

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/gemini-pro:generateContent")
        #expect(headerValue("x-goog-api-key", in: request) == nil)
    }

    @Test("uses global baseURL when location is global")
    func usesGlobalBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKChatResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "global",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        _ = try await model.doGenerate(options: .init(prompt: makePrompt()))

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1beta1/projects/test-project/locations/global/publishers/google/models/gemini-pro:generateContent")
    }

    @Test("uses express mode baseURL and injects x-goog-api-key when apiKey is provided")
    func usesExpressBaseURL_andInjectsApiKey() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKChatResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "KEY",
            fetch: fetch
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        _ = try await model.doGenerate(options: .init(prompt: makePrompt()))

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-pro:generateContent")
        #expect(headerValue("x-goog-api-key", in: request) == "KEY")
    }

    @Test("custom baseURL does not require project/location when apiKey is absent")
    func customBaseURL_doesNotRequireProjectLocationWhenApiKeyAbsent() async throws {
        let originalProject = getenv("GOOGLE_VERTEX_PROJECT").flatMap { String(validatingCString: $0) }
        let originalLocation = getenv("GOOGLE_VERTEX_LOCATION").flatMap { String(validatingCString: $0) }

        defer {
            if let originalProject {
                setenv("GOOGLE_VERTEX_PROJECT", originalProject, 1)
            } else {
                unsetenv("GOOGLE_VERTEX_PROJECT")
            }

            if let originalLocation {
                setenv("GOOGLE_VERTEX_LOCATION", originalLocation, 1)
            } else {
                unsetenv("GOOGLE_VERTEX_LOCATION")
            }
        }

        unsetenv("GOOGLE_VERTEX_PROJECT")
        unsetenv("GOOGLE_VERTEX_LOCATION")

        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makeOKChatResponse(url: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            fetch: fetch,
            baseURL: "https://custom-endpoint.example.com/"
        ))

        let model = try provider.languageModel(modelId: "gemini-pro")
        _ = try await model.doGenerate(options: .init(prompt: makePrompt()))

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://custom-endpoint.example.com/models/gemini-pro:generateContent")
        #expect(headerValue("x-goog-api-key", in: request) == nil)
    }
}
