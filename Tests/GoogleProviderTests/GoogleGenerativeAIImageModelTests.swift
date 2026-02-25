import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

private func makeImageConfig(fetch: @escaping FetchFunction) -> GoogleGenerativeAIImageModelConfig {
    GoogleGenerativeAIImageModelConfig(
        provider: "google.generative-ai",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        headers: { ["x-goog-api-key": "test"] },
        fetch: fetch,
        currentDate: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
}

@Suite("GoogleGenerativeAIImageModel")
struct GoogleGenerativeAIImageModelTests {
    @Test("should pass headers")
    func passHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": Data([0x01]).base64EncodedString()],
                ["bytesBase64Encoded": Data([0x02]).base64EncodedString()]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let modelWithHeaders = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["Custom-Provider-Header": "provider-header-value"] },
                fetch: fetch
            )
        )

        _ = try await modelWithHeaders.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected request to be captured")
            return
        }

        // Normalize headers to lowercase for comparison (matching upstream behavior)
        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("should respect maxImagesPerCall setting")
    func respectMaxImagesPerCallSetting() throws {
        let customModel = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(maxImagesPerCall: 2),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: nil
            )
        )

        if case let .value(maxImages) = customModel.maxImagesPerCall {
            #expect(maxImages == 2)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(2)")
        }
    }

    @Test("should use default maxImagesPerCall when not specified")
    func useDefaultMaxImagesPerCall() throws {
        let defaultModel = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: nil
            )
        )

        if case let .value(maxImages) = defaultModel.maxImagesPerCall {
            #expect(maxImages == 4)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(4)")
        }
    }

    @Test("should extract the generated images")
    func extractGeneratedImages() async throws {
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": "base64-image-1"],
                ["bytesBase64Encoded": "base64-image-2"]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            providerOptions: [:]
        ))

        if case let .base64(images) = result.images {
            #expect(images == ["base64-image-1", "base64-image-2"])
        } else {
            Issue.record("Expected base64 images")
        }
    }

    @Test("should default missing predictions to empty image list")
    func defaultMissingPredictionsToEmptyImageList() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [:])
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            providerOptions: [:]
        ))

        switch result.images {
        case .base64(let images):
            #expect(images.isEmpty)
        case .binary:
            Issue.record("Expected base64 images")
        }

        let metadata = result.providerMetadata?["google"]?.images ?? []
        #expect(metadata.isEmpty)
    }

    @Test("sends aspect ratio in the request")
    func sendAspectRatioInRequest() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [["bytesBase64Encoded": "base64-image-1"]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["instances"] != nil)
        if let parameters = json["parameters"] as? [String: Any] {
            #expect(parameters["sampleCount"] as? Int == 1)
            #expect(parameters["aspectRatio"] as? String == "16:9")
        } else {
            Issue.record("Expected parameters")
        }
    }

    @Test("should combine aspectRatio and provider options")
    func combineAspectRatioAndProviderOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [["bytesBase64Encoded": "base64-image-1"]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            aspectRatio: "1:1",
            providerOptions: [
                "google": [
                    "personGeneration": .string("dont_allow")
                ]
            ]
        ))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request body")
            return
        }

        if let parameters = json["parameters"] as? [String: Any] {
            #expect(parameters["sampleCount"] as? Int == 1)
            #expect(parameters["personGeneration"] as? String == "dont_allow")
            #expect(parameters["aspectRatio"] as? String == "1:1")
        } else {
            Issue.record("Expected parameters")
        }
    }

    @Test("should preserve explicit nullish provider options in parameters")
    func preserveExplicitNullishProviderOptionsInParameters() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [["bytesBase64Encoded": "base64-image-1"]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "test prompt",
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [
                "google": [
                    "personGeneration": .null,
                    "aspectRatio": .null
                ]
            ]
        ))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let parameters = json["parameters"] as? [String: Any] else {
            Issue.record("Missing request parameters")
            return
        }

        #expect(parameters["sampleCount"] as? Int == 1)
        #expect(parameters["personGeneration"] is NSNull)
        #expect(parameters["aspectRatio"] is NSNull)
    }

    @Test("should return warnings for unsupported settings")
    func returnWarningsForUnsupportedSettings() async throws {
        let responseJSON: [String: Any] = [
            "predictions": [["bytesBase64Encoded": "base64-image-1"]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024",
            aspectRatio: "1:1",
            seed: 123,
            providerOptions: [:]
        ))

        #expect(result.warnings.count == 2)
        let warning1 = result.warnings[0]
        if case let .unsupported(feature, details) = warning1 {
            #expect(feature == "size")
            #expect(details == "This model does not support the `size` option. Use `aspectRatio` instead.")
        } else {
            Issue.record("Expected unsupported warning for size")
        }

        let warning2 = result.warnings[1]
        if case let .unsupported(feature, details) = warning2 {
            #expect(feature == "seed")
            #expect(details == "This model does not support the `seed` option through this provider.")
        } else {
            Issue.record("Expected unsupported warning for seed")
        }
    }

    @Test("should include response data with timestamp, modelId and headers")
    func includeResponseDataWithTimestampModelIdAndHeaders() async throws {
        let responseJSON: [String: Any] = [
            "predictions": [["bytesBase64Encoded": "base64-image-1"]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "request-id": "test-request-id",
                "x-goog-quota-remaining": "123"
            ]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 1_710_504_000) // 2024-03-15T12:00:00Z

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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
        #expect(result.response.modelId == "imagen-3.0-generate-002")
        #expect(result.response.headers?["request-id"] == "test-request-id")
        #expect(result.response.headers?["x-goog-quota-remaining"] == "123")
    }

    @Test("should use real date when no custom date provider is specified")
    func useRealDateWhenNoCustomDateProvider() async throws {
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": "base64-image-1"],
                ["bytesBase64Encoded": "base64-image-2"]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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

        #expect(result.response.timestamp.timeIntervalSince1970 >= beforeDate.timeIntervalSince1970)
        #expect(result.response.timestamp.timeIntervalSince1970 <= afterDate.timeIntervalSince1970)
        #expect(result.response.modelId == "imagen-3.0-generate-002")
    }

    @Test("should only pass valid provider options")
    func onlyPassValidProviderOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": "base64-image-1"],
                ["bytesBase64Encoded": "base64-image-2"]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            aspectRatio: "16:9",
            providerOptions: [
                "google": [
                    "addWatermark": .bool(false),
                    "personGeneration": .string("allow_all"),
                    "foo": .string("bar"), // Invalid option
                    "negativePrompt": .string("negative prompt") // Invalid option
                ]
            ]
        ))

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request body")
            return
        }

        if let parameters = json["parameters"] as? [String: Any] {
            #expect(parameters["sampleCount"] as? Int == 2)
            #expect(parameters["personGeneration"] as? String == "allow_all")
            #expect(parameters["aspectRatio"] as? String == "16:9")
            // addWatermark should be filtered out (not valid in schema)
            #expect(parameters["addWatermark"] == nil)
            #expect(parameters["foo"] == nil)
            #expect(parameters["negativePrompt"] == nil)
        } else {
            Issue.record("Expected parameters")
        }
    }

    @Test("issues warnings for unsupported settings and maps response")
    func warningsAndResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": Data([0x01]).base64EncodedString()],
                ["bytesBase64Encoded": Data([0x02]).base64EncodedString()]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: makeImageConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "sunset",
            n: 2,
            size: "1024x1024",
            seed: 42,
            providerOptions: [
                "google": [
                    "personGeneration": .string("allow_all"),
                    "aspectRatio": .string("16:9")
                ]
            ]
        ))

        #expect(result.warnings.count == 2)
        if case let .base64(images) = result.images {
            #expect(images == [
                Data([0x01]).base64EncodedString(),
                Data([0x02]).base64EncodedString()
            ])
        } else {
            Issue.record("Expected base64 image payload")
        }
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 1_700_000_000))

        if let metadata = result.providerMetadata?["google"] {
            #expect(metadata.images.count == 2)
        } else {
            Issue.record("Expected provider metadata for google")
        }

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request payload")
            return
        }

        #expect(json["instances"] != nil)
        if let parameters = json["parameters"] as? [String: Any] {
            #expect(parameters["sampleCount"] as? Int == 2)
            // aspectRatio should be "16:9" from providerOptions (size is ignored)
            #expect(parameters["aspectRatio"] as? String == "16:9")
            #expect(parameters["personGeneration"] as? String == "allow_all")
        } else {
            Issue.record("Expected parameters object")
        }
    }

    @Test("gemini image model should use maxImagesPerCall=10 by default")
    func geminiDefaultMaxImagesPerCall() throws {
        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: nil
            )
        )

        if case let .value(maxImages) = model.maxImagesPerCall {
            #expect(maxImages == 10)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(10)")
        }
    }

    @Test("gemini image model should support responseModalities/imageConfig and map usage")
    func geminiRequestAndUsageMapping() async throws {
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
                "promptTokenCount": 20,
                "candidatesTokenCount": 200,
                "totalTokenCount": 220
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let responseURL = URL(string: "https://api.example.com/v1beta/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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
        #expect(usage.inputTokens == 20)
        #expect(usage.outputTokens == 200)
        #expect(usage.totalTokens == 220)

        let googleMetadata = try #require(result.providerMetadata?["google"])
        #expect(googleMetadata.images.count == 1)

        let request = try #require(await capture.value())
        #expect(request.url?.absoluteString == "https://api.example.com/v1beta/models/gemini-2.5-flash-image:generateContent")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try #require(json["generationConfig"] as? [String: Any])
        #expect(generationConfig["responseModalities"] as? [String] == ["IMAGE"])

        let imageConfig = try #require(generationConfig["imageConfig"] as? [String: Any])
        #expect(imageConfig["aspectRatio"] as? String == "16:9")

        let contents = try #require(json["contents"] as? [[String: Any]])
        let first = try #require(contents.first)
        let parts = try #require(first["parts"] as? [[String: Any]])
        let firstPart = try #require(parts.first)
        #expect(firstPart["text"] as? String == "A beautiful sunset")
    }

    @Test("gemini image model should include usage with zero total when usageMetadata is missing")
    func geminiUsageMissingMapsToZeroTotal() async throws {
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
        let responseURL = URL(string: "https://api.example.com/v1beta/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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

        let request = try #require(await capture.value())
        #expect(request.url?.absoluteString == "https://api.example.com/v1beta/models/gemini-2.5-flash-image:generateContent")
    }

    @Test("gemini image model should include url and file inputs in request")
    func geminiInputFilesMapping() async throws {
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
        let responseURL = URL(string: "https://api.example.com/v1beta/models/gemini-2.5-flash-image:generateContent")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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

        let request = try #require(await capture.value())
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
        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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
        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
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

    @Test("gemini image model should respect custom maxImagesPerCall")
    func geminiCustomMaxImagesPerCall() throws {
        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "gemini-2.5-flash-image"),
            settings: .init(maxImagesPerCall: 5),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: nil
            )
        )

        if case let .value(maxImages) = model.maxImagesPerCall {
            #expect(maxImages == 5)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(5)")
        }
    }

    @Test("imagen model should reject editing with files and mask")
    func imagenRejectsEditingInputs() async throws {
        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-4.0-generate-001"),
            settings: .init(),
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://api.example.com/v1beta",
                headers: { ["api-key": "test-api-key"] },
                fetch: nil
            )
        )

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                providerOptions: [:],
                files: [
                    .file(mediaType: "image/png", data: .base64("base64-source-image"), providerOptions: nil)
                ]
            ))
        }

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                providerOptions: [:],
                mask: .file(mediaType: "image/png", data: .base64("base64-mask-image"), providerOptions: nil)
            ))
        }
    }
}
