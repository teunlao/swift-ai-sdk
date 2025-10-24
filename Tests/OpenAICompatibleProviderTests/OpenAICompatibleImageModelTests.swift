import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Tests for OpenAICompatibleImageModel.

 Port of `@ai-sdk/openai-compatible/src/image/openai-compatible-image-model.test.ts`.
 */

@Suite("OpenAICompatibleImageModel")
struct OpenAICompatibleImageModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private let prompt = "A photorealistic astronaut riding a horse"

    @Test("should expose correct provider and model information")
    func modelInformation() throws {
        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" }
            )
        )

        #expect(model.provider == "openai-compatible")
        #expect(model.modelId == "dall-e-3")
        #expect(model.specificationVersion == "v3")
        if case .value(let max) = model.maxImagesPerCall {
            #expect(max == 10)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(10)")
        }
    }

    @Test("should pass the correct parameters")
    func passCorrectParameters() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "test1234"],
                ["b64_json": "test5678"]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: prompt,
                n: 2,
                size: "1024x1024",
                providerOptions: ["openai": ["quality": .string("hd")]]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == prompt)
        #expect(json["n"] as? Double == 2)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["quality"] as? String == "hd")
        #expect(json["response_format"] as? String == "b64_json")
    }

    @Test("should add warnings for unsupported settings")
    func warningsForUnsupportedSettings() async throws {
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: prompt,
                n: 1,
                aspectRatio: "16:9",
                seed: 123
            )
        )

        #expect(result.warnings.count == 2)

        let aspectRatioWarning = result.warnings.first { warning in
            if case .unsupportedSetting(let setting, _) = warning {
                return setting == "aspectRatio"
            }
            return false
        }

        let seedWarning = result.warnings.first { warning in
            if case .unsupportedSetting(let setting, _) = warning {
                return setting == "seed"
            }
            return false
        }

        #expect(aspectRatioWarning != nil)
        #expect(seedWarning != nil)
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Custom-Provider-Header": "provider-header-value"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: prompt,
                n: 1,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }

    @Test("should handle API errors with custom error structure")
    func customErrorStructure() async throws {
        let errorJSON: [String: Any] = [
            "status": "error",
            "details": [
                "errorMessage": "Custom provider error format",
                "errorCode": 1234
            ]
        ]

        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL, statusCode: 400)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(errorData), urlResponse: httpResponse)
        }

        let customErrorConfig = OpenAICompatibleErrorConfiguration(
            failedResponseHandler: createJsonErrorResponseHandler(
                errorSchema: CustomErrorSchema.schema,
                errorToMessage: { data in
                    "Error \(data.details.errorCode): \(data.details.errorMessage)"
                }
            ),
            extractMessage: { json in
                let data = try JSONEncoder().encode(json)
                let payload = try JSONDecoder().decode(CustomErrorSchema.self, from: data)
                return "Error \(payload.details.errorCode): \(payload.details.errorMessage)"
            }
        )

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch,
                errorConfiguration: customErrorConfig
            )
        )

        do {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(prompt: prompt, n: 1)
            )
            Issue.record("Expected error to be thrown")
        } catch let error as APICallError {
            #expect(error.message == "Error 1234: Custom provider error format")
            #expect(error.statusCode == 400)
            #expect(error.url == "https://api.example.com/dall-e-3/images/generations")
        }
    }

    @Test("should handle API errors with default error structure")
    func defaultErrorStructure() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "message": "Invalid prompt content",
                "type": "invalid_request_error",
                "param": NSNull(),
                "code": NSNull()
            ]
        ]

        let errorData = try JSONSerialization.data(withJSONObject: errorJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL, statusCode: 400)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(errorData), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        do {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(prompt: prompt, n: 1)
            )
            Issue.record("Expected error to be thrown")
        } catch let error as APICallError {
            #expect(error.message == "Invalid prompt content")
            #expect(error.statusCode == 400)
            #expect(error.url == "https://api.example.com/dall-e-3/images/generations")
        }
    }

    @Test("should return the raw b64_json content")
    func returnRawB64Content() async throws {
        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "test1234"],
                ["b64_json": "test5678"]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(prompt: prompt, n: 2)
        )

        if case .base64(let images) = result.images {
            #expect(images.count == 2)
            #expect(images[0] == "test1234")
            #expect(images[1] == "test5678")
        } else {
            Issue.record("Expected base64 images")
        }
    }

    @Test("should include timestamp, headers and modelId in response")
    func responseMetadata() async throws {
        let testDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01T00:00:00Z
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch,
                currentDate: { testDate }
            )
        )

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(prompt: prompt, n: 1)
        )

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "dall-e-3")
        #expect(result.response.headers != nil)
    }

    @Test("should use real date when no custom date provider is specified")
    func useRealDate() async throws {
        let beforeDate = Date()

        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(prompt: prompt, n: 1)
        )

        let afterDate = Date()

        #expect(result.response.timestamp >= beforeDate)
        #expect(result.response.timestamp <= afterDate)
        #expect(result.response.modelId == "dall-e-3")
    }

    @Test("should pass the user setting in the request")
    func passUserSetting() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: prompt,
                n: 1,
                size: "1024x1024",
                providerOptions: ["openai": ["user": .string("test-user-id")]]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == prompt)
        #expect(json["n"] as? Double == 1)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["user"] as? String == "test-user-id")
        #expect(json["response_format"] as? String == "b64_json")
    }

    @Test("should not include user field in request when not set via provider options")
    func noUserFieldWhenNotSet() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "test1234"]]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/dall-e-3/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: "dall-e-3"),
            config: OpenAICompatibleImageModelConfig(
                provider: "openai-compatible",
                headers: { ["Authorization": "Bearer test-key"] },
                url: { options in "https://api.example.com/\(options.modelId)\(options.path)" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: prompt,
                n: 1,
                size: "1024x1024",
                providerOptions: ["openai": [:]]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == prompt)
        #expect(json["n"] as? Double == 1)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["response_format"] as? String == "b64_json")
        #expect(json["user"] == nil)
    }
}

// Custom error schema for testing
private struct CustomErrorSchema: Codable {
    struct Details: Codable {
        let errorMessage: String
        let errorCode: Int
    }

    let status: String
    let details: Details

    static let schema = FlexibleSchema(
        Schema<CustomErrorSchema>.codable(
            CustomErrorSchema.self,
            jsonSchema: .object(["type": .string("object")])
        )
    )
}
