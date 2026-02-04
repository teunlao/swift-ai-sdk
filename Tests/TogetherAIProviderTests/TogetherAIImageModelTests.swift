import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import TogetherAIProvider

@Suite("TogetherAIImageModel")
struct TogetherAIImageModelTests {
    private func makeModel(
        baseURL: String = "https://api.example.com",
        headers: @escaping @Sendable () -> [String: String?] = { ["api-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> TogetherAIImageModel {
        TogetherAIImageModel(
            modelId: "stabilityai/stable-diffusion-xl",
            config: TogetherAIImageModelConfig(
                provider: "togetherai",
                baseURL: baseURL,
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    @Test("passes correct parameters including size and seed")
    func passesParameters() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()

        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "test-base64-content"]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                size: "1024x1024",
                aspectRatio: nil,
                seed: 42,
                providerOptions: ["togetherai": ["additional_param": .string("value")]],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.example.com/images/generations")
        #expect(json["model"] as? String == "stabilityai/stable-diffusion-xl")
        #expect(json["prompt"] as? String == "A cute baby sea otter")
        #expect(json["seed"] as? Double == 42)
        #expect(json["width"] as? Double == 1024)
        #expect(json["height"] as? Double == 1024)
        #expect(json["response_format"] as? String == "base64")
        #expect(json["additional_param"] as? String == "value")
    }

    @Test("includes n when requesting multiple images")
    func includesNParameter() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()

        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "a"],
                ["b64_json": "b"],
                ["b64_json": "c"],
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 3,
                size: "1024x1024",
                aspectRatio: nil,
                seed: 42,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["n"] as? Double == 3)
    }

    @Test("passes headers")
    func passesHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()

        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(
            headers: { ["Custom-Provider-Header": "provider-header-value"] },
            fetch: fetch
        )

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: ["Custom-Request-Header": "request-header-value"],
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headerFields = request.allHTTPHeaderFields ?? [:]
        let headers = headerFields.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["content-type"] == "application/json")
    }

    @Test("handles API errors")
    func handlesAPIErrors() async throws {
        let responseJSON: [String: Any] = [
            "error": ["message": "Bad Request"]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        await #expect(throws: APICallError.self) {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: "p",
                    n: 1,
                    size: nil,
                    aspectRatio: nil,
                    seed: nil,
                    providerOptions: [:],
                    abortSignal: nil,
                    headers: nil,
                    files: nil,
                    mask: nil
                )
            )
        }
    }

    @Test("returns aspectRatio warning when aspectRatio is provided")
    func returnsAspectRatioWarning() async throws {
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 1,
                size: "1024x1024",
                aspectRatio: "1:1",
                seed: 123,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        #expect(result.warnings == [
            .unsupported(
                feature: "aspectRatio",
                details: "This model does not support the `aspectRatio` option. Use `size` instead."
            )
        ])
    }

    @Test("respects abort signal")
    func respectsAbortSignal() async throws {
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        await #expect(throws: CancellationError.self) {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: "p",
                    n: 1,
                    size: nil,
                    aspectRatio: nil,
                    seed: nil,
                    providerOptions: [:],
                    abortSignal: { true },
                    headers: nil,
                    files: nil,
                    mask: nil
                )
            )
        }
    }

    @Test("includes timestamp, headers and modelId in response")
    func includesResponseMetadata() async throws {
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-request-id": "req-1"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
        let model = makeModel(fetch: fetch, currentDate: { date })

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "p",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        #expect(result.response.timestamp == date)
        #expect(result.response.modelId == "stabilityai/stable-diffusion-xl")
        #expect(result.response.headers?["x-request-id"] == "req-1")
        switch result.images {
        case .base64(let images):
            #expect(images == ["x"])
        default:
            Issue.record("Expected base64 images")
        }
    }

    @Test("exposes correct provider and model information")
    func constructorExposesMetadata() throws {
        let model = makeModel()
        #expect(model.provider == "togetherai")
        #expect(model.modelId == "stabilityai/stable-diffusion-xl")
        #expect(model.specificationVersion == "v3")
        switch model.maxImagesPerCall {
        case .value(let maxImages):
            #expect(maxImages == 1)
        default:
            Issue.record("Expected maxImagesPerCall == 1")
        }
    }

    @Test("sends image_url when url file is provided")
    func sendsImageURLForURLFile() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Make the shirt yellow",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: [
                    .url(url: "https://example.com/input.jpg", providerOptions: nil)
                ],
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["image_url"] as? String == "https://example.com/input.jpg")
    }

    @Test("converts binary file to data URI")
    func convertsBinaryFileToDataURI() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let data = Data([137, 80, 78, 71, 13, 10, 26, 10])

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Transform this image",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: [
                    .file(mediaType: "image/png", data: .binary(data), providerOptions: nil)
                ],
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        guard let imageURL = json["image_url"] as? String else {
            Issue.record("Expected image_url")
            return
        }

        #expect(imageURL.hasPrefix("data:image/png;base64,"))
    }

    @Test("converts base64 file data to data URI")
    func convertsBase64StringFileToDataURI() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Edit this",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: [
                    .file(mediaType: "image/png", data: .base64(base64), providerOptions: nil)
                ],
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(
            json["image_url"] as? String ==
                "data:image/png;base64,\(base64)"
        )
    }

    @Test("throws error when mask is provided")
    func throwsOnMask() async throws {
        let model = makeModel(fetch: { _ in
            Issue.record("fetch should not be called when mask is provided")
            throw CancellationError()
        })

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: "Inpaint this area",
                    n: 1,
                    size: nil,
                    aspectRatio: nil,
                    seed: nil,
                    providerOptions: [:],
                    abortSignal: nil,
                    headers: nil,
                    files: [
                        .url(url: "https://example.com/input.jpg", providerOptions: nil)
                    ],
                    mask: .url(url: "https://example.com/mask.png", providerOptions: nil)
                )
            )
        }
    }

    @Test("warns when multiple files are provided and only uses the first")
    func warnsOnMultipleFiles() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Edit multiple images",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: [
                    .url(url: "https://example.com/input1.jpg", providerOptions: nil),
                    .url(url: "https://example.com/input2.jpg", providerOptions: nil),
                ],
                mask: nil
            )
        )

        #expect(result.warnings == [
            .other(message: "Together AI only supports a single input image. Additional images are ignored.")
        ])

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["image_url"] as? String == "https://example.com/input1.jpg")
    }

    @Test("passes provider options with image editing")
    func passesProviderOptions() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let responseJSON: [String: Any] = ["data": [["b64_json": "x"]]]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/images/generations")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Transform the style",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [
                    "togetherai": [
                        "steps": .number(28),
                        "guidance": .number(3.5),
                    ]
                ],
                abortSignal: nil,
                headers: nil,
                files: [
                    .url(url: "https://example.com/input.jpg", providerOptions: nil)
                ],
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["steps"] as? Double == 28)
        #expect(json["guidance"] as? Double == 3.5)
        #expect(json["image_url"] as? String == "https://example.com/input.jpg")
    }
}
