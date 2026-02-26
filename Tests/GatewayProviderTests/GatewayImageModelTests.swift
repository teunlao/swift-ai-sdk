import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayImageModel")
struct GatewayImageModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(for request: URLRequest, statusCode: Int = 200, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        modelId: GatewayImageModelId = GatewayImageModelId(rawValue: "google/imagen-4.0-generate-001"),
        fetch: @escaping FetchFunction,
        o11yHeaders: [String: String] = [:],
        provider: String = "gateway"
    ) -> GatewayImageModel {
        GatewayImageModel(
            modelId: modelId,
            config: GatewayImageModelConfig(
                provider: provider,
                baseURL: "https://api.test.com",
                headers: { () async throws -> [String: String?] in
                    [
                        "Authorization": "Bearer test-token",
                        GATEWAY_AUTH_METHOD_HEADER: "api-key",
                    ]
                },
                fetch: fetch,
                o11yHeaders: { () async throws -> [String: String?] in
                    o11yHeaders.mapValues { Optional($0) }
                }
            )
        )
    }

    @Test("constructor exposes modelId/provider/specVersion and avoids client-side splitting")
    func constructorProperties() async throws {
        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(Data(#"{"images":["ok"]}"#.utf8)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        #expect(model.modelId == "google/imagen-4.0-generate-001")
        #expect(model.provider == "gateway")
        #expect(model.specificationVersion == "v3")

        guard case .value(let max) = model.maxImagesPerCall else {
            Issue.record("Expected fixed maxImagesPerCall")
            return
        }
        #expect(max == Int.max)

        let customProvider = makeModel(fetch: fetch, provider: "custom-gateway")
        #expect(customProvider.provider == "custom-gateway")
    }

    @Test("doGenerate sends correct headers/body and maps base64 images")
    func doGenerateHeadersBodyAndResponseMapping() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "images": ["base64-image-1"],
            "usage": [
                "inputTokens": 27,
                "outputTokens": 6240,
                "totalTokens": 6267,
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json", "X-Test": "1"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let o11yHeaders: [String: String] = [
            "ai-o11y-deployment-id": "dpl_123",
            "ai-o11y-environment": "production",
        ]

        let model = makeModel(fetch: fetch, o11yHeaders: o11yHeaders)
        let result = try await model.doGenerate(options: .init(
            prompt: "A cat playing piano",
            n: 1,
            size: "1024x1024",
            aspectRatio: "16:9",
            seed: 42,
            providerOptions: ["vertex": ["safetySettings": .string("block_none")]],
            headers: ["Custom-Header": "test-value"]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.test.com/image-model")

        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-token")
        #expect(headers["custom-header"] == "test-value")
        #expect(headers["ai-image-model-specification-version"] == "3")
        #expect(headers["ai-model-id"] == "google/imagen-4.0-generate-001")
        for (key, value) in o11yHeaders {
            #expect(headers[key] == value)
        }

        #expect(json["prompt"] as? String == "A cat playing piano")
        #expect((json["n"] as? Double) == 1 || (json["n"] as? Int) == 1)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["aspectRatio"] as? String == "16:9")
        #expect((json["seed"] as? Double) == 42 || (json["seed"] as? Int) == 42)

        guard let providerOptions = json["providerOptions"] as? [String: Any],
              let vertex = providerOptions["vertex"] as? [String: Any]
        else {
            Issue.record("Expected providerOptions.vertex")
            return
        }
        #expect(vertex["safetySettings"] as? String == "block_none")

        guard case .base64(let images) = result.images else {
            Issue.record("Expected base64 images")
            return
        }
        #expect(images == ["base64-image-1"])
        #expect(result.warnings == [])

        #expect(result.response.modelId == "google/imagen-4.0-generate-001")
        #expect(result.response.headers?["content-type"] == "application/json")
        #expect(result.response.headers?["x-test"] == "1")

        #expect(result.usage == ImageModelV3Usage(inputTokens: 27, outputTokens: 6240, totalTokens: 6267))
    }

    @Test("doGenerate omits optional parameters when not provided (but includes empty providerOptions)")
    func doGenerateOmitsOptionalParameters() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(Data(#"{"images":["ok"]}"#.utf8)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: "A simple prompt",
            n: 1,
            providerOptions: [:]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["prompt"] as? String == "A simple prompt")
        #expect((json["n"] as? Double) == 1 || (json["n"] as? Int) == 1)
        #expect(json["providerOptions"] != nil)

        #expect(json["size"] == nil)
        #expect(json["aspectRatio"] == nil)
        #expect(json["seed"] == nil)
        #expect(json["files"] == nil)
        #expect(json["mask"] == nil)
    }

    @Test("doGenerate encodes ImageModelV3File binary data to base64 strings and preserves providerOptions")
    func doGenerateEncodesFiles() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(Data(#"{"images":["ok"]}"#.utf8)), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let binary = Data([72, 101, 108, 108, 111]) // "Hello"
        let expectedBase64 = binary.base64EncodedString()

        _ = try await model.doGenerate(options: .init(
            prompt: "Test prompt",
            n: 1,
            providerOptions: [:],
            files: [
                .file(
                    mediaType: "image/png",
                    data: .binary(binary),
                    providerOptions: ["fal": ["enhanceImage": .bool(true)]]
                ),
                .file(
                    mediaType: "image/png",
                    data: .base64("already-base64-encoded"),
                    providerOptions: nil
                ),
                .url(url: "https://example.com/image.png", providerOptions: nil),
            ],
            mask: .file(mediaType: "image/png", data: .binary(binary), providerOptions: nil)
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              files.count == 3,
              let mask = json["mask"] as? [String: Any]
        else {
            Issue.record("Expected files and mask in request body")
            return
        }

        #expect(files[0]["type"] as? String == "file")
        #expect(files[0]["mediaType"] as? String == "image/png")
        #expect(files[0]["data"] as? String == expectedBase64)

        guard let file0ProviderOptions = files[0]["providerOptions"] as? [String: Any],
              let fal = file0ProviderOptions["fal"] as? [String: Any]
        else {
            Issue.record("Expected files[0].providerOptions.fal")
            return
        }
        #expect(fal["enhanceImage"] as? Bool == true)

        #expect(files[1]["data"] as? String == "already-base64-encoded")
        #expect(files[2]["type"] as? String == "url")
        #expect(files[2]["url"] as? String == "https://example.com/image.png")

        #expect(mask["type"] as? String == "file")
        #expect(mask["data"] as? String == expectedBase64)
    }

    @Test("doGenerate converts gateway providerMetadata into ImageModelV3ProviderMetadataValue")
    func doGenerateProviderMetadataConversion() async throws {
        let responseBody: [String: Any] = [
            "images": ["base64-1"],
            "providerMetadata": [
                "vertex": [
                    "images": [
                        ["revisedPrompt": "Revised prompt 1"],
                        ["revisedPrompt": "Revised prompt 2"],
                    ],
                ],
                "gateway": [
                    "routing": ["provider": "vertex"],
                    "cost": "0.08",
                ],
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))

        guard let metadata = result.providerMetadata else {
            Issue.record("Expected providerMetadata")
            return
        }

        #expect(metadata.keys.contains("vertex"))
        #expect(metadata.keys.contains("gateway"))

        let vertex = try #require(metadata["vertex"])
        #expect(vertex.images.count == 2)
        if case .object(let first) = vertex.images[0] {
            #expect(first["revisedPrompt"] == .string("Revised prompt 1"))
        } else {
            Issue.record("Expected vertex.images[0] object")
        }

        let gateway = try #require(metadata["gateway"])
        #expect(gateway.images == [])
        if case .object(let additional)? = gateway.additionalData {
            #expect(additional["cost"] == .string("0.08"))
            #expect(additional["routing"] != nil)
        } else {
            Issue.record("Expected gateway.additionalData object")
        }
    }

    @Test("doGenerate handles warnings and providerMetadata presence/absence")
    func doGenerateWarningsAndProviderMetadataPresence() async throws {
        let responseBodyWithWarnings: [String: Any] = [
            "images": ["base64-1"],
            "warnings": [
                ["type": "other", "message": "Setting not supported"],
                ["type": "unsupported", "feature": "size", "details": "Use aspectRatio instead."],
            ],
            "providerMetadata": [:],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBodyWithWarnings, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))

        #expect(result.warnings == [
            .other(message: "Setting not supported"),
            .unsupported(feature: "size", details: "Use aspectRatio instead.")
        ])

        #expect(result.providerMetadata != nil)
        #expect(result.providerMetadata?.isEmpty == true)

        let fetchWithoutMetadata: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(Data(#"{"images":["base64-1"]}"#.utf8)), urlResponse: httpResponse)
        }

        let modelWithoutMetadata = makeModel(fetch: fetchWithoutMetadata)
        let resultWithoutMetadata = try await modelWithoutMetadata.doGenerate(options: .init(prompt: "Test", n: 1, providerOptions: [:]))
        #expect(resultWithoutMetadata.providerMetadata == nil)
        #expect(resultWithoutMetadata.warnings == [])
    }
}
