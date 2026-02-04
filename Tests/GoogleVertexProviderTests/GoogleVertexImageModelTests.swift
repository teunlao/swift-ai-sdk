import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexImageModel")
struct GoogleVertexImageModelTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?

        func set(_ request: URLRequest) {
            lastRequest = request
        }
    }

    private func headerValue(_ name: String, in request: URLRequest) -> String? {
        request.allHTTPHeaderFields?.first(where: { $0.key.lowercased() == name.lowercased() })?.value
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    private func makePredictionsResponse(
        url: URL,
        predictions: [[String: Any]],
        headers: [String: String] = [:]
    ) throws -> FetchResponse {
        let body: [String: Any] = [
            "predictions": predictions
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var headerFields = headers
        headerFields["Content-Type"] = headerFields["Content-Type"] ?? "application/json"
        headerFields["Content-Length"] = headerFields["Content-Length"] ?? "\(data.count)"

        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headerFields
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    private func makeModel(fetch: @escaping FetchFunction) -> GoogleVertexImageModel {
        GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "imagen-3.0-generate-002"),
            config: GoogleVertexImageModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch
            )
        )
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 1",
                        "bytesBase64Encoded": "base64-image-1"
                    ],
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 2",
                        "bytesBase64Encoded": "base64-image-2",
                        "someFutureField": "some future value"
                    ]
                ]
            )
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch,
            baseURL: "https://api.example.com"
        ))

        let model = try provider.imageModel(modelId: "imagen-3.0-generate-002")
        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")

        let userAgent = try #require(headerValue("user-agent", in: request))
        #expect(userAgent.contains("ai-sdk/google-vertex/\(GOOGLE_VERTEX_VERSION)"))
    }

    @Test("should use default maxImagesPerCall when not specified")
    func defaultMaxImagesPerCall() throws {
        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "imagen-3.0-generate-002"),
            config: GoogleVertexImageModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: nil
            )
        )

        switch model.maxImagesPerCall {
        case .value(let value):
            #expect(value == 4)
        case .default, .function:
            Issue.record("Expected maxImagesPerCall to be a fixed value")
        }
    }

    @Test("should extract the generated images")
    func extractGeneratedImages() async throws {
        let fetch: FetchFunction = { request in
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 1",
                        "bytesBase64Encoded": "base64-image-1"
                    ],
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 2",
                        "bytesBase64Encoded": "base64-image-2"
                    ]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:]
        ))

        switch result.images {
        case .base64(let images):
            #expect(images == ["base64-image-1", "base64-image-2"])
        case .binary:
            Issue.record("Expected base64 images")
        }
    }

    @Test("sends aspect ratio in the request")
    func sendsAspectRatioInRequest() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let instances = try #require(dict["instances"] as? [[String: Any]])
        let firstInstance = try #require(instances.first)
        #expect(firstInstance["prompt"] as? String == "test prompt")

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters["aspectRatio"] as? String == "16:9")
        #expect(parameters["sampleCount"] as? Double == 1)
    }

    @Test("should pass seed directly when specified")
    func passSeedDirectly() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            seed: 42,
            providerOptions: [:]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters["sampleCount"] as? Double == 1)
        #expect(parameters["seed"] as? Double == 42)
    }

    @Test("should combine aspectRatio, seed and provider options")
    func combineAspectRatioSeedAndProviderOptions() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            aspectRatio: "1:1",
            seed: 42,
            providerOptions: [
                "vertex": [
                    "addWatermark": .bool(false)
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters["addWatermark"] as? Bool == false)
        #expect(parameters["aspectRatio"] as? String == "1:1")
        #expect(parameters["sampleCount"] as? Double == 1)
        #expect(parameters["seed"] as? Double == 42)
    }

    @Test("should return warnings for unsupported settings")
    func warningsForUnsupportedSettings() async throws {
        let fetch: FetchFunction = { request in
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024",
            aspectRatio: "1:1",
            seed: 123,
            providerOptions: [:]
        ))

        #expect(result.warnings == [
            .unsupported(
                feature: "size",
                details: "This model does not support the `size` option. Use `aspectRatio` instead."
            )
        ])
    }

    @Test("should include response data with timestamp, modelId and headers")
    func responseInfo_includesTimestampModelIdAndHeaders() async throws {
        let testDate = try #require(ISO8601DateFormatter().date(from: "2024-03-15T12:00:00Z"))
        let modelId = "imagen-3.0-generate-002"

        let fetch: FetchFunction = { request in
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 1",
                        "bytesBase64Encoded": "base64-image-1"
                    ],
                ],
                headers: [
                    "request-id": "test-request-id",
                    "x-goog-quota-remaining": "123"
                ]
            )
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: modelId),
            config: GoogleVertexImageModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            providerOptions: [:]
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == modelId)

        let headers = try #require(result.response.headers)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["content-length"] != nil)
        #expect(headers["request-id"] == "test-request-id")
        #expect(headers["x-goog-quota-remaining"] == "123")
    }

    @Test("should use real date when no custom date provider is specified")
    func usesRealDateWhenNoCustomDateProviderSpecified() async throws {
        let fetch: FetchFunction = { request in
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"],
                    ["bytesBase64Encoded": "base64-image-2"]
                ]
            )
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "imagen-3.0-generate-002"),
            config: GoogleVertexImageModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch
            )
        )

        let beforeDate = Date()
        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:]
        ))
        let afterDate = Date()

        #expect(result.response.timestamp >= beforeDate)
        #expect(result.response.timestamp <= afterDate)
        #expect(result.response.modelId == "imagen-3.0-generate-002")
    }

    @Test("should only pass valid provider options")
    func onlyPassValidProviderOptions() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    ["bytesBase64Encoded": "base64-image-1"],
                    ["bytesBase64Encoded": "base64-image-2"]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            aspectRatio: "16:9",
            providerOptions: [
                "vertex": [
                    "addWatermark": .bool(false),
                    "negativePrompt": .string("negative prompt"),
                    "personGeneration": .string("allow_all"),
                    "sampleImageSize": .string("2K"),
                    "foo": .string("bar")
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters["addWatermark"] as? Bool == false)
        #expect(parameters["aspectRatio"] as? String == "16:9")
        #expect(parameters["negativePrompt"] as? String == "negative prompt")
        #expect(parameters["personGeneration"] as? String == "allow_all")
        #expect(parameters["sampleCount"] as? Double == 2)
        #expect(parameters["sampleImageSize"] as? String == "2K")
        #expect(parameters["foo"] == nil)
    }

    @Test("should return image meta data")
    func returnImageMetaData() async throws {
        let fetch: FetchFunction = { request in
            return try makePredictionsResponse(
                url: try #require(request.url),
                predictions: [
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 1",
                        "bytesBase64Encoded": "base64-image-1"
                    ],
                    [
                        "mimeType": "image/png",
                        "prompt": "revised prompt 2",
                        "bytesBase64Encoded": "base64-image-2"
                    ]
                ]
            )
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:]
        ))

        let vertex = try #require(result.providerMetadata?["vertex"])
        #expect(vertex.images == [
            .object(["revisedPrompt": .string("revised prompt 1")]),
            .object(["revisedPrompt": .string("revised prompt 2")]),
        ])
    }
}
