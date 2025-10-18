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
            url: { _ in "https://api.openai.com/v1/images/generations" },
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
}
