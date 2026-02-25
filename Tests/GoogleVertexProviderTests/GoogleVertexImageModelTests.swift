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

    @Test("should preserve explicit nullish provider options in parameters")
    func preserveExplicitNullishProviderOptionsInParameters() async throws {
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
            providerOptions: [
                "vertex": [
                    "negativePrompt": .null,
                    "addWatermark": .null,
                    "sampleImageSize": .null
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters["sampleCount"] as? Double == 1)
        #expect(parameters["aspectRatio"] as? String == "16:9")
        #expect(parameters["negativePrompt"] is NSNull)
        #expect(parameters["addWatermark"] is NSNull)
        #expect(parameters["sampleImageSize"] is NSNull)
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

    @Test("gemini image model should use maxImagesPerCall=10")
    func geminiDefaultMaxImagesPerCall() throws {
        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: nil
            )
        )

        switch model.maxImagesPerCall {
        case .value(let value):
            #expect(value == 10)
        case .default, .function:
            Issue.record("Expected maxImagesPerCall to be a fixed value")
        }
    }

    @Test("gemini image model should map request and usage through language API")
    func geminiRequestAndUsageMapping() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "inlineData": [
                                    "mimeType": "image/png",
                                    "data": "base64-generated-image"
                                ]
                            ]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 10,
                "candidatesTokenCount": 100,
                "totalTokenCount": 110
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let responseURL = URL(string: "https://api.example.com/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: "A beautiful sunset",
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        if case let .base64(images) = result.images {
            #expect(images == ["base64-generated-image"])
        } else {
            Issue.record("Expected base64 images")
        }

        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 10)
        #expect(usage.outputTokens == 100)
        #expect(usage.totalTokens == 110)

        let vertexMetadata = try #require(result.providerMetadata?["vertex"])
        #expect(vertexMetadata.images.count == 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://api.example.com/models/gemini-2.5-flash-image:generateContent")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try #require(json["generationConfig"] as? [String: Any])
        #expect(generationConfig["responseModalities"] as? [String] == ["IMAGE"])
        let imageConfig = try #require(generationConfig["imageConfig"] as? [String: Any])
        #expect(imageConfig["aspectRatio"] as? String == "16:9")
    }

    @Test("gemini image model should include usage with zero total when usageMetadata is missing")
    func geminiUsageMissingMapsToZeroTotal() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "inlineData": [
                                    "mimeType": "image/png",
                                    "data": "base64-generated-image"
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
        let responseURL = URL(string: "https://api.example.com/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: "A beautiful sunset",
            n: 1,
            providerOptions: [:]
        ))

        let usage = try #require(result.usage)
        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == nil)
        #expect(usage.totalTokens == 0)
    }

    @Test("gemini image model should include url and file input parts")
    func geminiInputFilesMapping() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "inlineData": [
                                    "mimeType": "image/png",
                                    "data": "base64-generated-image"
                                ]
                            ]
                        ],
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
        let responseURL = URL(string: "https://api.example.com/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.set(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit this image",
            n: 1,
            providerOptions: [:],
            files: [
                .file(mediaType: "image/png", data: .base64("base64-source-image"), providerOptions: nil),
                .url(url: "https://example.com/cat.png", providerOptions: nil)
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(json["contents"] as? [[String: Any]])
        let first = try #require(contents.first)
        let parts = try #require(first["parts"] as? [[String: Any]])

        #expect(parts.count == 3)
        #expect(parts[0]["text"] as? String == "Edit this image")

        let inlineData = try #require(parts[1]["inlineData"] as? [String: Any])
        #expect(inlineData["mimeType"] as? String == "image/png")
        #expect(inlineData["data"] as? String == "base64-source-image")

        let fileData = try #require(parts[2]["fileData"] as? [String: Any])
        #expect(fileData["mimeType"] as? String == "image/jpeg")
        #expect(fileData["fileUri"] as? String == "https://example.com/cat.png")
    }

    @Test("gemini image model should reject unsupported n and mask")
    func geminiRejectsUnsupportedOptions() async throws {
        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: nil
            )
        )

        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(
                prompt: "A beautiful sunset",
                n: 2,
                providerOptions: [:]
            ))
        }

        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                providerOptions: [:],
                mask: .file(mediaType: "image/png", data: .base64("base64-mask-image"), providerOptions: nil)
            ))
        }
    }

    @Test("gemini image model should reject relative file URLs")
    func geminiRejectsRelativeFileURLs() async throws {
        let model = GoogleVertexImageModel(
            modelId: GoogleVertexImageModelId(rawValue: "gemini-2.5-flash-image"),
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
                fetch: nil
            )
        )

        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                providerOptions: [:],
                files: [
                    .url(url: "cat.png", providerOptions: nil)
                ]
            ))
        }
    }
}
