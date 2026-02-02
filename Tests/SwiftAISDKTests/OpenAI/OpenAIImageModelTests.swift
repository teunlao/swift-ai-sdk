import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let imagePrompt = "A cute baby sea otter"

@Suite("OpenAIImageModel")
struct OpenAIImageModelTests {
    private func makeConfig(
        providerHeaders: @escaping @Sendable () -> [String: String?] = { ["Authorization": "Bearer test-api-key"] },
        fetch: @escaping FetchFunction
    ) -> OpenAIConfig {
        OpenAIConfig(
            provider: "openai.image",
            url: { options in "https://api.openai.com/v1\(options.path)" },
            headers: providerHeaders,
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_733_837_122) })
        )
    }

    private func makeResponseJSON() -> [String: Any] {
        [
            "created": 1_733_837_122,
            "data": [
                [
                    "revised_prompt": "Revised prompt text",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]
    }

    @Test("doGenerate sends request body including provider options")
    func testDoGenerateSendsRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(modelId: "dall-e-3", config: makeConfig(fetch: fetch))

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "openai": ["style": .string("vivid")]
                ],
                abortSignal: nil,
                headers: ["Custom-Header": "request"]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == imagePrompt)
        #expect(json["n"] as? Int == 1 || json["n"] as? Double == 1)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["style"] as? String == "vivid")
        #expect(json["response_format"] as? String == "b64_json")

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalized["authorization"] == "Bearer test-api-key")
        #expect(normalized["custom-header"] == "request")
        #expect(normalized["content-type"] == "application/json")
    }

    @Test("doGenerate returns images, warnings and metadata")
    func testDoGenerateReturnsImagesAndWarnings() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(modelId: "dall-e-3", config: makeConfig(fetch: fetch))

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "512x512",
                aspectRatio: "1:1",
                seed: 42,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        if case .base64(let images) = result.images {
            #expect(images == ["base64-image-1", "base64-image-2"])
        } else {
            Issue.record("Expected base64 images")
        }

        #expect(result.warnings.count == 2)
        if result.warnings.count == 2 {
            if case .unsupportedSetting(let setting, let details) = result.warnings[0] {
                #expect(setting == "aspectRatio")
                #expect(details == "This model does not support aspect ratio. Use `size` instead.")
            } else {
                Issue.record("Unexpected warning type")
            }
            if case .unsupportedSetting(let setting, _) = result.warnings[1] {
                #expect(setting == "seed")
            } else {
                Issue.record("Unexpected warning type")
            }
        }

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata.images == [
                .object(["revisedPrompt": .string("Revised prompt text")]),
                .null
            ])
        } else {
            Issue.record("Missing provider metadata")
        }

        #expect(result.response.timestamp == Date(timeIntervalSince1970: 1_733_837_122))
        #expect(result.response.modelId == "dall-e-3")
    }

    @Test("doGenerate respects provider custom current date")
    func testDoGenerateUsesInjectedTimestamp() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.image",
            url: { _ in "https://api.openai.com/v1/images/generations" },
            headers: { [:] },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 86_400) })
        )

        let model = OpenAIImageModel(modelId: "dall-e-3", config: config)

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "256x256",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        #expect(result.response.timestamp == Date(timeIntervalSince1970: 86_400))
    }

    @Test("response_format omitted for gpt-image-1")
    func testResponseFormatOmittedForGPTImage1() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "gpt-image-1",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-image-1")
        #expect(json["response_format"] == nil)
    }

    @Test("response_format omitted for date-suffixed gpt-image-1 (Azure deployment name)")
    func testResponseFormatOmittedForDateSuffixedGPTImage1() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "gpt-image-1-2024-12-17",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-image-1-2024-12-17")
        #expect(json["response_format"] == nil)
    }

    @Test("response_format omitted for date-suffixed gpt-image-1-mini (Azure deployment name)")
    func testResponseFormatOmittedForDateSuffixedGPTImage1Mini() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "gpt-image-1-mini-2024-12-17",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-image-1-mini-2024-12-17")
        #expect(json["response_format"] == nil)
    }

    @Test("response_format omitted for gpt-image-1.5")
    func testResponseFormatOmittedForGPTImageOnePointFive() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "gpt-image-1.5",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-image-1.5")
        #expect(json["response_format"] == nil)
    }

    @Test("response_format omitted for date-suffixed gpt-image-1.5 (Azure deployment name)")
    func testResponseFormatOmittedForDateSuffixedGPTImageOnePointFive() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "gpt-image-1.5-2024-12-17",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["model"] as? String == "gpt-image-1.5-2024-12-17")
        #expect(json["response_format"] == nil)
    }

    // Port of should pass headers
    @Test("doGenerate passes custom headers and organization/project")
    func testDoGeneratePassesHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/images/generations" },
            headers: {
                [
                    "Authorization": "Bearer test-api-key",
                    "OpenAI-Organization": "test-organization",
                    "OpenAI-Project": "test-project",
                    "Custom-Provider-Header": "provider-header-value"
                ]
            },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_733_837_122) })
        )

        let model = OpenAIImageModel(modelId: "dall-e-3", config: config)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "openai": ["style": .string("vivid")]
                ],
                abortSignal: nil,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })

        #expect(normalized["authorization"] == "Bearer test-api-key")
        #expect(normalized["content-type"] == "application/json")
        #expect(normalized["custom-provider-header"] == "provider-header-value")
        #expect(normalized["custom-request-header"] == "request-header-value")
        #expect(normalized["openai-organization"] == "test-organization")
        #expect(normalized["openai-project"] == "test-project")
    }

    // Port of should respect maxImagesPerCall setting
    @Test("maxImagesPerCall returns correct values for different models")
    func testMaxImagesPerCall() throws {
        let provider = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: "test-api-key"))

        let dalleE2Model = try provider.imageModel(modelId: "dall-e-2")
        // Swift adaptation: enum case instead of direct number
        if case .value(let count) = dalleE2Model.maxImagesPerCall {
            #expect(count == 10)
        } else {
            Issue.record("Expected .value(10) for dall-e-2 maxImagesPerCall")
        }

        let unknownModel = try provider.imageModel(modelId: "unknown-model")
        // Swift adaptation: enum case instead of direct number
        if case .value(let count) = unknownModel.maxImagesPerCall {
            #expect(count == 1)
        } else {
            Issue.record("Expected .value(1) for unknown model maxImagesPerCall")
        }

        let gptImageOnePointFiveModel = try provider.imageModel(modelId: "gpt-image-1.5")
        if case .value(let count) = gptImageOnePointFiveModel.maxImagesPerCall {
            #expect(count == 10)
        } else {
            Issue.record("Expected .value(10) for gpt-image-1.5 maxImagesPerCall")
        }
    }

    // Port of should include response data with timestamp, modelId and headers
    @Test("doGenerate includes response metadata with custom headers")
    func testDoGenerateIncludesResponseMetadata() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "x-request-id": "test-request-id",
                "x-ratelimit-remaining": "123"
            ]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let testDate = Date(timeIntervalSince1970: 1_615_824_000) // 2021-03-15T12:00:00Z

        let config = OpenAIConfig(
            provider: "test-provider",
            url: { _ in "https://api.openai.com/v1/images/generations" },
            headers: { [:] },
            fetch: fetch,
            _internal: .init(currentDate: { testDate })
        )

        let model = OpenAIImageModel(modelId: "dall-e-3", config: config)

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "dall-e-3")

        let responseHeaders = result.response.headers ?? [:]
        #expect(responseHeaders["content-type"] == "application/json")
        #expect(responseHeaders["x-request-id"] == "test-request-id")
        #expect(responseHeaders["x-ratelimit-remaining"] == "123")
    }

    // Port of should use real date when no custom date provider is specified
    @Test("doGenerate uses real date when no custom date provider specified")
    func testDoGenerateUsesRealDate() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        // Create config without custom date provider (uses default)
        let config = OpenAIConfig(
            provider: "openai.image",
            url: { _ in "https://api.openai.com/v1/images/generations" },
            headers: { [:] },
            fetch: fetch
        )

        let model = OpenAIImageModel(modelId: "dall-e-3", config: config)

        let beforeDate = Date()

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        let afterDate = Date()

        #expect(result.response.timestamp.timeIntervalSince1970 >= beforeDate.timeIntervalSince1970)
        #expect(result.response.timestamp.timeIntervalSince1970 <= afterDate.timeIntervalSince1970)
        #expect(result.response.modelId == "dall-e-3")
    }

    // Port of should include response_format for dall-e-3
    @Test("response_format included for dall-e-3")
    func testResponseFormatIncludedForDallE3() async throws {
        actor RequestCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(
            modelId: "dall-e-3",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let data = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing request body")
            return
        }

        #expect(json["response_format"] as? String == "b64_json")
    }

    // Port of should return image meta data
    @Test("doGenerate returns image metadata with revised prompts")
    func testDoGenerateReturnsImageMetadata() async throws {
        let responseJSON: [String: Any] = [
            "created": 1_733_837_122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(modelId: "dall-e-3", config: makeConfig(fetch: fetch))

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "openai": ["style": .string("vivid")]
                ],
                abortSignal: nil,
                headers: nil
            )
        )

        guard let metadata = result.providerMetadata?["openai"] else {
            Issue.record("Missing provider metadata")
            return
        }

        #expect(metadata.images == [
            .object([
                "revisedPrompt": .string("A charming visual illustration of a baby sea otter swimming joyously.")
            ]),
            .null
        ])
    }

    @Test("doGenerate calls /images/edits with multipart form-data when files are provided")
    func testDoGenerateUsesEditsEndpointWhenFilesProvided() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/edits")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(modelId: "dall-e-2", config: makeConfig(fetch: fetch))
        let inputFile: ImageModelV3File = .file(
            mediaType: "image/png",
            data: .binary(Data("PNGDATA".utf8)),
            providerOptions: nil
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: nil,
                providerOptions: ["openai": ["style": .string("vivid")]],
                abortSignal: nil,
                headers: ["Custom-Header": "request"],
                files: [inputFile],
                mask: nil
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        let contentType = normalized["content-type"] ?? ""
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        guard let body = request.httpBody else {
            Issue.record("Missing multipart body")
            return
        }
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("name=\"model\""))
        #expect(bodyString.contains("dall-e-2"))
        #expect(bodyString.contains("name=\"prompt\""))
        #expect(bodyString.contains(imagePrompt))
        #expect(bodyString.contains("name=\"image\""))
        #expect(bodyString.contains("filename=\"image.png\""))
        #expect(bodyString.lowercased().contains("content-type: image/png"))
        #expect(bodyString.contains("PNGDATA"))
        #expect(bodyString.contains("name=\"style\""))
        #expect(bodyString.contains("vivid"))
    }

    @Test("doGenerate includes mask part when provided")
    func testDoGenerateIncludesMaskWhenProvided() async throws {
        actor BodyCapture {
            var body: Data?
            func store(_ data: Data?) { body = data }
            func current() -> Data? { body }
        }

        let capture = BodyCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeResponseJSON())
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/images/edits")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIImageModel(modelId: "dall-e-2", config: makeConfig(fetch: fetch))
        let inputFile: ImageModelV3File = .file(
            mediaType: "image/png",
            data: .binary(Data("IMG".utf8)),
            providerOptions: nil
        )
        let mask: ImageModelV3File = .file(
            mediaType: "image/png",
            data: .binary(Data("MASK".utf8)),
            providerOptions: nil
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: imagePrompt,
                n: 1,
                size: "256x256",
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: [inputFile],
                mask: mask
            )
        )

        guard let body = await capture.current() else {
            Issue.record("Missing request body")
            return
        }
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("name=\"mask\""))
        #expect(bodyString.contains("filename=\"mask.png\""))
        #expect(bodyString.contains("MASK"))
    }
}
