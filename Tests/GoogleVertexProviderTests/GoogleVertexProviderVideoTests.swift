import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexProvider (video)")
struct GoogleVertexProviderVideoTests {
    actor RequestCapture {
        private(set) var requests: [URLRequest] = []

        func append(_ request: URLRequest) {
            requests.append(request)
        }

        func first() -> URLRequest? {
            requests.first
        }
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func jsonResponse(url: URL, body: Any) throws -> FetchResponse {
        let data = try jsonData(body)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    @Test("creates video model and uses regional baseURL")
    func regionalBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = try #require(request.url)

            if url.absoluteString.contains(":predictLongRunning") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": false
                    ]
                )
            }

            if url.absoluteString.contains(":fetchPredictOperation") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": true,
                        "response": [
                            "videos": [
                                ["bytesBase64Encoded": "video-data", "mimeType": "video/mp4"]
                            ]
                        ]
                    ]
                )
            }

            Issue.record("Unexpected URL: \(url.absoluteString)")
            throw CancellationError()
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch,
            accessTokenProvider: { "test-access-token" }
        ))

        let model = provider.video(modelId: .veo20Generate001)
        #expect(model.provider == "google.vertex.video")
        #expect(model.modelId == "veo-2.0-generate-001")

        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: "hello",
            n: 1,
            providerOptions: ["vertex": ["pollIntervalMs": .number(10)]]
        ))

        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/veo-2.0-generate-001:predictLongRunning")
    }

    @Test("creates video model via videoModel(modelId:)")
    func videoModelLookup() throws {
        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project"
        ))

        let maybeModel = try provider.videoModel(modelId: "veo-3.0-generate-001")
        guard let model = maybeModel else {
            Issue.record("Expected video model")
            return
        }

        #expect(model.provider == "google.vertex.video")
        #expect(model.modelId == "veo-3.0-generate-001")
    }

    @Test("uses global region baseURL for video model")
    func globalRegionBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = try #require(request.url)

            if url.absoluteString.contains(":predictLongRunning") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": false
                    ]
                )
            }

            if url.absoluteString.contains(":fetchPredictOperation") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": true,
                        "response": [
                            "videos": [
                                ["bytesBase64Encoded": "video-data", "mimeType": "video/mp4"]
                            ]
                        ]
                    ]
                )
            }

            Issue.record("Unexpected URL: \(url.absoluteString)")
            throw CancellationError()
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "global",
            project: "test-project",
            fetch: fetch,
            accessTokenProvider: { "test-access-token" }
        ))

        let model = provider.video(modelId: .veo30Generate001)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: "hello",
            n: 1,
            providerOptions: ["vertex": ["pollIntervalMs": .number(10)]]
        ))

        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1beta1/projects/test-project/locations/global/publishers/google/models/veo-3.0-generate-001:predictLongRunning")
    }

    @Test("uses custom baseURL for video model")
    func customBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let url = try #require(request.url)

            if url.absoluteString.contains(":predictLongRunning") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": false
                    ]
                )
            }

            if url.absoluteString.contains(":fetchPredictOperation") {
                return try jsonResponse(
                    url: url,
                    body: [
                        "name": "operations/test-op",
                        "done": true,
                        "response": [
                            "videos": [
                                ["bytesBase64Encoded": "video-data", "mimeType": "video/mp4"]
                            ]
                        ]
                    ]
                )
            }

            Issue.record("Unexpected URL: \(url.absoluteString)")
            throw CancellationError()
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch,
            baseURL: "https://custom-endpoint.example.com/"
        ))

        let model = provider.video(modelId: GoogleVertexVideoModelId.veo20Generate001)
        _ = try await model.doGenerate(options: VideoModelV3CallOptions(
            prompt: "hello",
            n: 1,
            providerOptions: ["vertex": ["pollIntervalMs": .number(10)]]
        ))

        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == "https://custom-endpoint.example.com/models/veo-2.0-generate-001:predictLongRunning")
    }
}
