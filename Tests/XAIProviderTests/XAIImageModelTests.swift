import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import XAIProvider

/**
 Tests for XAIImageModel.

 Port of `@ai-sdk/xai/src/xai-image-model.test.ts`.
 */
@Suite("XAIImageModel")
struct XAIImageModelTests {
    private let prompt = "A cute baby sea otter"
    private let imageURL = "https://api.example.com/images/generated.png"

    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func first() -> URLRequest? { requests.first }
        func last() -> URLRequest? { requests.last }
    }

    private func httpResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func decodeRequestBodyJSON(_ request: URLRequest) throws -> JSONValue {
        let body = try #require(request.httpBody)
        return try JSONDecoder().decode(JSONValue.self, from: body)
    }

    private func makeModel(
        headers: @escaping @Sendable () throws -> [String: String?] = { ["api-key": "test-key"] },
        fetch: @escaping FetchFunction,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) -> XAIImageModel {
        XAIImageModel(
            modelId: "grok-2-image",
            config: XAIImageModelConfig(
                provider: "xai.image",
                baseURL: "https://api.example.com",
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func makeFetch(
        capture: RequestCapture,
        postResponseBody: Any,
        getResponseBody: Data = Data("test-binary-content".utf8),
        statusCode: Int = 200,
        headerFields: [String: String] = ["Content-Type": "application/json"]
    ) throws -> FetchFunction {
        let postData = try JSONSerialization.data(withJSONObject: postResponseBody, options: [.sortedKeys])

        return { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://api.example.com/images/generations" || url == "https://api.example.com/images/edits" {
                await capture.append(request)
                return FetchResponse(
                    body: .data(postData),
                    urlResponse: self.httpResponse(url: request.url!, statusCode: statusCode, headers: headerFields)
                )
            }

            if url == self.imageURL {
                return FetchResponse(
                    body: .data(getResponseBody),
                    urlResponse: self.httpResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "image/png"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }
    }

    @Test("constructor exposes correct provider/model info")
    func constructorInfo() throws {
        let fetch: FetchFunction = { _ in
            throw CancellationError()
        }
        let model = makeModel(fetch: fetch)

        #expect(model.provider == "xai.image")
        #expect(model.modelId == "grok-2-image")
        #expect(model.specificationVersion == "v4")

        switch model.maxImagesPerCall {
        case .value(let value):
            #expect(value == 3)
        default:
            Issue.record("Expected maxImagesPerCall == .value(1)")
        }
    }

    @Test("doGenerate sends correct parameters for generation")
    func generateParameters() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            aspectRatio: "16:9",
            providerOptions: [:]
        ))

        let request = try #require(await capture.first())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.example.com/images/generations")

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "model": .string("grok-2-image"),
            "prompt": .string(prompt),
            "n": .number(1),
            "response_format": .string("b64_json"),
            "aspect_ratio": .string("16:9"),
        ]))
    }

    @Test("doGenerate sends correct parameters for editing (binary file)")
    func editParametersBinaryFile() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Turn the cat into a dog",
            n: 1,
            files: [
                .file(
                    mediaType: "image/png",
                    data: .binary(Data([137, 80, 78, 71])),
                    providerOptions: nil
                )
            ]
        ))

        let request = try #require(await capture.first())
        #expect(request.url?.absoluteString == "https://api.example.com/images/edits")

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "model": .string("grok-2-image"),
            "prompt": .string("Turn the cat into a dog"),
            "n": .number(1),
            "response_format": .string("b64_json"),
            "image": .object([
                "url": .string("data:image/png;base64,iVBORw=="),
                "type": .string("image_url"),
            ])
        ]))
    }

    @Test("doGenerate sends URL-based file as image_url")
    func editParametersURLFile() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit this image",
            n: 1,
            files: [
                .url(url: "https://example.com/input.png", providerOptions: nil)
            ]
        ))

        let request = try #require(await capture.first())
        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "model": .string("grok-2-image"),
            "prompt": .string("Edit this image"),
            "n": .number(1),
            "response_format": .string("b64_json"),
            "image": .object([
                "url": .string("https://example.com/input.png"),
                "type": .string("image_url"),
            ])
        ]))
    }

    @Test("doGenerate sends base64 file as data URI")
    func editParametersBase64File() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: "Edit this image",
            n: 1,
            files: [
                .file(
                    mediaType: "image/png",
                    data: .base64("iVBORw0KGgoAAAANSUhEUgAAAAE="),
                    providerOptions: nil
                )
            ]
        ))

        let request = try #require(await capture.first())
        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "model": .string("grok-2-image"),
            "prompt": .string("Edit this image"),
            "n": .number(1),
            "response_format": .string("b64_json"),
            "image": .object([
                "url": .string("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAE="),
                "type": .string("image_url"),
            ])
        ]))
    }

    @Test("downloads images from returned URLs")
    func downloadsImages() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        guard case .binary(let images) = result.images else {
            Issue.record("Expected binary images")
            return
        }
        #expect(images.count == 1)
        #expect(String(data: images[0], encoding: .utf8) == "test-binary-content")
    }

    @Test("passes headers from model config and request options")
    func passesHeaders() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(
            headers: { ["Custom-Provider-Header": "provider-header-value"] },
            fetch: fetch
        )

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [:],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let request = try #require(await capture.first())
        let normalized = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }

        #expect(normalized["content-type"] == "application/json")
        #expect(normalized["custom-provider-header"] == "provider-header-value")
        #expect(normalized["custom-request-header"] == "request-header-value")
    }

    @Test("passes provider options")
    func passesProviderOptions() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "xai": [
                    "output_format": .string("jpeg"),
                    "sync_mode": .bool(true),
                ]
            ]
        ))

        let request = try #require(await capture.first())
        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "model": .string("grok-2-image"),
            "prompt": .string(prompt),
            "n": .number(1),
            "response_format": .string("b64_json"),
            "output_format": .string("jpeg"),
            "sync_mode": .bool(true),
        ]))
    }

    @Test("includes revised_prompt in providerMetadata")
    func revisedPromptProviderMetadata() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL, "revised_prompt": "A revised prompt"]]]
        )
        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        guard let xaiMetadata = result.providerMetadata?["xai"] else {
            Issue.record("Missing xai provider metadata")
            return
        }

        #expect(xaiMetadata.images.count == 1)
        guard case .object(let imageMetadata) = xaiMetadata.images[0] else {
            Issue.record("Expected image metadata object")
            return
        }
        #expect(imageMetadata["revisedPrompt"] == .string("A revised prompt"))
    }

    @Test("response metadata includes timestamp, modelId and headers")
    func includesResponseMetadata() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]],
            headerFields: ["Content-Type": "application/json", "x-request-id": "test-request-id"]
        )

        let testDate = Date(timeIntervalSince1970: 0)
        let model = makeModel(fetch: fetch, currentDate: { testDate })

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == "grok-2-image")
        #expect(result.response.headers?["x-request-id"] == "test-request-id")
    }

    @Test("warnings: size/seed/mask/multiple files")
    func warnings() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: ["data": [["url": imageURL]]]
        )
        let model = makeModel(fetch: fetch)

        let sizeResult = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            providerOptions: [:]
        ))
        #expect(sizeResult.warnings.contains(.unsupported(
            feature: "size",
            details: "This model does not support the `size` option. Use `aspectRatio` instead."
        )))

        let seedResult = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            seed: 42,
            providerOptions: [:]
        ))
        #expect(seedResult.warnings.contains(.unsupported(feature: "seed", details: nil)))

        let maskResult = try await model.doGenerate(options: .init(
            prompt: "Edit this",
            n: 1,
            files: [
                .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            ],
            mask: .file(mediaType: "image/png", data: .binary(Data([255, 255, 255, 0])), providerOptions: nil)
        ))
        #expect(maskResult.warnings.contains(.unsupported(feature: "mask", details: nil)))

        let multiFileResult = try await model.doGenerate(options: .init(
            prompt: "Edit images",
            n: 1,
            files: [
                .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
                .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil),
            ]
        ))
        let multiRequest = try #require(await capture.last())
        #expect(multiFileResult.warnings.isEmpty)
        #expect(multiRequest.url?.path == "/images/edits")
        guard case .object(let multiBody) = try decodeRequestBodyJSON(multiRequest) else { Issue.record("Missing image edit request"); return }
        #expect(multiBody["images"] == .array([
            .object(["url": .string("data:image/png;base64,iVBORw=="), "type": .string("image_url")]),
            .object(["url": .string("data:image/png;base64,iVBORw=="), "type": .string("image_url")])
        ]))
    }

    private static let mediaDownloads: [(String, String)] = [
        ("http://127.0.0.1:8080/v1", "http://127.0.0.1:8080/media/image.png"),
        ("https://api.example.com/v1", "https://media.example.com/image.png"),
        ("https://api.example.com/v1", "https://cdn.example.org/image.png")
    ]

    @Test("returned image URLs receive only User-Agent on configured, sibling and foreign origins", arguments: mediaDownloads)
    func downloadHeaderIsolation(_ baseURL: String, _ imageURL: String) async throws {
        let image = Data([137, 80, 78, 71])
        let provider = createXai(settings: .init(baseURL: baseURL, apiKey: "secret", headers: ["Cookie": "provider-cookie", "X-Api-Key": "custom-secret", "X-Provider": "provider"], fetch: { request in
            if request.httpMethod == "POST" {
                #expect(request.url?.absoluteString == "\(baseURL)/images/generations")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
                #expect(request.value(forHTTPHeaderField: "Cookie") == "caller-cookie")
                #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "custom-secret")
                #expect(request.value(forHTTPHeaderField: "X-Caller") == "caller")
                let data = try JSONEncoder().encode(JSONValue.object(["data": .array([.object(["url": .string(imageURL)])])]))
                return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"]))
            }
            #expect(request.url?.absoluteString == imageURL)
            #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == Set(["user-agent"]))
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("caller-agent") == true)
            #expect(request.fetchRedirectMode == .manual)
            return FetchResponse(body: .data(image), urlResponse: self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "image/png"]))
        }))
        let result = try await provider.image(modelId: "grok-imagine-image").doGenerate(options: .init(prompt: "otter", n: 1, headers: ["Cookie": "caller-cookie", "X-Caller": "caller", "uSeR-aGeNt": "caller-agent"]))
        #expect(result.images == .binary([image]))
    }

    @Test("returned image redirects keep header isolation and validate every hop")
    func downloadRedirectIsolation() async throws {
        let provider = createXai(settings: .init(baseURL: "https://api.example.com/v1", apiKey: "secret", headers: ["Cookie": "secret", "X-Custom": "custom"], fetch: { request in
            if request.httpMethod == "POST" {
                return FetchResponse(body: .data(Data(#"{"data":[{"url":"https://api.example.com/image.png"}]}"#.utf8)), urlResponse: self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"]))
            }
            #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == Set(["user-agent"]))
            #expect(request.fetchRedirectMode == .manual)
            if request.url?.absoluteString == "https://api.example.com/image.png" {
                return FetchResponse(body: .data(Data()), urlResponse: self.httpResponse(url: request.url!, statusCode: 302, headers: ["Location": "https://cdn.example.org/final.png"]))
            }
            #expect(request.url?.absoluteString == "https://cdn.example.org/final.png")
            return FetchResponse(body: .data(Data([1, 2, 3])), urlResponse: self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "image/png"]))
        }))
        let result = try await provider.image(modelId: "grok-imagine-image").doGenerate(options: .init(prompt: "otter", n: 1))
        #expect(result.images == .binary([Data([1, 2, 3])]))
    }

    @Test("returned image redirects cannot reach an untrusted private host")
    func downloadPrivateRedirect() async throws {
        let provider = createXai(settings: .init(baseURL: "https://api.example.com/v1", apiKey: "secret", fetch: { request in
            if request.httpMethod == "POST" {
                return FetchResponse(body: .data(Data(#"{"data":[{"url":"https://api.example.com/image.png"}]}"#.utf8)), urlResponse: self.httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"]))
            }
            #expect(request.url?.absoluteString == "https://api.example.com/image.png")
            return FetchResponse(body: .data(Data()), urlResponse: self.httpResponse(url: request.url!, statusCode: 302, headers: ["Location": "http://127.0.0.1:9090/private.png"]))
        }))
        await #expect(throws: DownloadError.self) {
            _ = try await provider.image(modelId: "grok-imagine-image").doGenerate(options: .init(prompt: "otter", n: 1))
        }
    }

    @Test("base64 images preserve billing metadata and image capabilities")
    func base64Images() async throws {
        let capture = RequestCapture()
        let fetch = try makeFetch(capture: capture, postResponseBody: ["data": [["b64_json": "AQID", "revised_prompt": "otter"]], "usage": ["cost_in_usd_ticks": 7]])
        let model = XAIImageModel(modelId: "grok-imagine-image-pro", config: .init(provider: "xai.image", baseURL: "https://api.example.com", headers: { [:] }, fetch: fetch))
        #expect(try await model.supportsFileInputs == true)
        #expect(try await model.supportsMaskInputs == false)
        let result = try await model.doGenerate(options: .init(prompt: prompt, n: 1, providerOptions: ["xai": ["resolution": .string("2k"), "quality": .string("high"), "user": .string("user")]]))
        #expect(result.images == .base64(["AQID"]))
        #expect(result.providerMetadata?["xai"]?.additionalData == .object(["costInUsdTicks": .number(7)]))
        let request = try #require(await capture.first())
        guard case .object(let body) = try decodeRequestBodyJSON(request) else { Issue.record("Missing request"); return }
        #expect(body["resolution"] == .string("2k"))
        #expect(body["quality"] == .string("high"))
        #expect(body["user"] == .string("user"))
    }

    @Test("moderation rejections fail before downloading an image")
    func moderation() async throws {
        let capture = RequestCapture()
        let model = makeModel(fetch: try makeFetch(capture: capture, postResponseBody: ["data": [["respect_moderation": false]]]))
        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model.doGenerate(options: .init(prompt: prompt, n: 1))
        }
    }

    @Test("handles API errors")
    func apiErrors() async throws {
        let capture = RequestCapture()
        let errorBody: [String: Any] = [
            "error": [
                "message": "Invalid prompt",
                "type": "invalid_request_error",
            ]
        ]
        let fetch = try makeFetch(
            capture: capture,
            postResponseBody: errorBody,
            statusCode: 400
        )
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                providerOptions: [:]
            ))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Invalid prompt")
            #expect(error.statusCode == 400)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("respects abort signal")
    func abortSignal() async throws {
        final class AbortFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var aborted: Bool = false

            func set(_ value: Bool) {
                lock.lock()
                aborted = value
                lock.unlock()
            }

            func isAborted() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return aborted
            }
        }

        let flag = AbortFlag()
        let fetch: FetchFunction = { request in
            try await Task.sleep(nanoseconds: 500_000_000)
            return FetchResponse(
                body: .data(Data("{\"data\":[{\"url\":\"\(self.imageURL)\"}]}".utf8)),
                urlResponse: self.httpResponse(
                    url: request.url!,
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"]
                )
            )
        }

        let model = makeModel(fetch: fetch)

        let task = Task {
            try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                providerOptions: [:],
                abortSignal: { flag.isAborted() }
            ))
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        flag.set(true)

        do {
            _ = try await task.value
            Issue.record("Expected abort")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
    }
}
