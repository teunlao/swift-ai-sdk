import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import DeepInfraProvider

@Suite("DeepInfraImageModel")
struct DeepInfraImageModelTests {
    private static let prompt = "A cute baby sea otter"

    private static func makeModel(
        modelId: DeepInfraImageModelId = "stability-ai/sdxl",
        provider: String = "deepinfra",
        baseURL: String = "https://api.example.com",
        headers: @escaping @Sendable () -> [String: String?] = { ["api-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) -> DeepInfraImageModel {
        DeepInfraImageModel(
            modelId: modelId,
            config: DeepInfraImageModelConfig(
                provider: provider,
                baseURL: baseURL,
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private static func httpResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Suite("doGenerate (standard)", .serialized)
    struct StandardGenerateTests {
        private let prompt = "A cute baby sea otter"

        @Test("passes correct parameters including aspect ratio and seed")
        func passesCorrectParametersIncludingAspectRatioAndSeed() async throws {
            actor Capture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let capture = Capture()
            let responseJSON: [String: Any] = [
                "images": ["data:image/png;base64,test-image-data"],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)
            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                size: nil,
                aspectRatio: "16:9",
                seed: 42,
                providerOptions: ["deepinfra": ["additional_param": .string("value")]],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            ))

            guard let body = await capture.value()?.httpBody else {
                Issue.record("Expected request body")
                return
            }

            let parsed = try JSONDecoder().decode(JSONValue.self, from: body)
            #expect(parsed == .object([
                "prompt": .string(prompt),
                "aspect_ratio": .string("16:9"),
                "seed": .number(42),
                "num_images": .number(1),
                "additional_param": .string("value"),
            ]))
        }

        @Test("calls the correct url")
        func callsTheCorrectUrl() async throws {
            actor Capture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let capture = Capture()
            let responseJSON: [String: Any] = [
                "images": ["data:image/png;base64,test-image-data"],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)
            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            ))

            let request = await capture.value()
            #expect(request?.httpMethod == "POST")
            #expect(request?.url?.absoluteString == "https://api.example.com/stability-ai/sdxl")
        }

        @Test("passes headers")
        func passesHeaders() async throws {
            actor Capture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let capture = Capture()
            let responseJSON: [String: Any] = [
                "images": ["data:image/png;base64,test-image-data"],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
            }

            let model = DeepInfraImageModelTests.makeModel(
                headers: { ["Custom-Provider-Header": "provider-header-value"] },
                fetch: fetch
            )

            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: ["Custom-Request-Header": "request-header-value"],
                files: nil,
                mask: nil
            ))

            guard let headers = await capture.value()?.allHTTPHeaderFields else {
                Issue.record("Expected request headers")
                return
            }

            let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            #expect(normalized["content-type"] == "application/json")
            #expect(normalized["custom-provider-header"] == "provider-header-value")
            #expect(normalized["custom-request-header"] == "request-header-value")
        }

        @Test("handles API errors")
        func handlesAPIErrors() async throws {
            let errorBody = try JSONSerialization.data(withJSONObject: ["error": ["message": "Bad Request"]])
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { _ in
                FetchResponse(
                    body: .data(errorBody),
                    urlResponse: DeepInfraImageModelTests.httpResponse(url: url, statusCode: 400, headers: ["Content-Type": "application/json"])
                )
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)

            do {
                _ = try await model.doGenerate(options: .init(prompt: prompt, n: 1))
                Issue.record("Expected API error")
            } catch let error as APICallError {
                #expect(error.message == "Bad Request")
            }
        }

        @Test("handles size parameter")
        func handlesSizeParameter() async throws {
            actor Capture {
                var body: Data?
                func store(_ data: Data?) { self.body = data }
                func value() -> Data? { body }
            }

            let capture = Capture()
            let responseJSON: [String: Any] = [
                "images": ["data:image/png;base64,test-image-data"],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { request in
                await capture.store(request.httpBody)
                return FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)
            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                size: "1024x768",
                aspectRatio: nil,
                seed: 42,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            ))

            guard let body = await capture.value() else {
                Issue.record("Expected request body")
                return
            }

            let parsed = try JSONDecoder().decode(JSONValue.self, from: body)
            #expect(parsed == .object([
                "prompt": .string(prompt),
                "width": .string("1024"),
                "height": .string("768"),
                "seed": .number(42),
                "num_images": .number(1),
            ]))
        }

        @Test("respects abort signal")
        func respectsAbortSignal() async throws {
            let fetch: FetchFunction = { _ in
                Issue.record("Fetch should not be called when aborted before request")
                throw URLError(.cancelled)
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)

            do {
                _ = try await model.doGenerate(options: .init(
                    prompt: prompt,
                    n: 1,
                    abortSignal: { true }
                ))
                Issue.record("Expected CancellationError")
            } catch is CancellationError {
                // ok
            }
        }

        @Test("strips data URL prefix from returned images")
        func stripsDataURLPrefixFromReturnedImages() async throws {
            let responseJSON: [String: Any] = [
                "images": ["data:image/png;base64,test-image-data"],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
            let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

            let fetch: FetchFunction = { _ in
                FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
            }

            let model = DeepInfraImageModelTests.makeModel(fetch: fetch)
            let result = try await model.doGenerate(options: .init(prompt: prompt, n: 1))

            guard case let .base64(images) = result.images else {
                Issue.record("Expected base64 images")
                return
            }
            #expect(images == ["test-image-data"])
        }

        @Suite("response metadata")
        struct ResponseMetadataTests {
            @Test("includes timestamp, headers and modelId in response")
            func includesTimestampHeadersAndModelIdInResponse() async throws {
                let testDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
                let responseJSON: [String: Any] = [
                    "images": ["data:image/png;base64,test-image-data"],
                ]
                let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
                let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

                let fetch: FetchFunction = { _ in
                    FetchResponse(body: .data(responseData), urlResponse: DeepInfraImageModelTests.httpResponse(url: url))
                }

                let model = DeepInfraImageModelTests.makeModel(
                    fetch: fetch,
                    currentDate: { testDate }
                )

                let result = try await model.doGenerate(options: .init(prompt: DeepInfraImageModelTests.prompt, n: 1))
                #expect(result.response.timestamp == testDate)
                #expect(result.response.modelId == "stability-ai/sdxl")
                #expect(result.response.headers?.isEmpty == false)
            }

            @Test("includes response headers from API call")
            func includesResponseHeadersFromAPICall() async throws {
                let responseJSON: [String: Any] = [
                    "images": ["data:image/png;base64,test-image-data"],
                ]
                let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
                let url = URL(string: "https://api.example.com/stability-ai/sdxl")!

                let fetch: FetchFunction = { _ in
                    FetchResponse(
                        body: .data(responseData),
                        urlResponse: DeepInfraImageModelTests.httpResponse(
                            url: url,
                            headers: [
                                "Content-Type": "application/json",
                                "Content-Length": "52",
                                "x-request-id": "test-request-id",
                            ]
                        )
                    )
                }

                let model = DeepInfraImageModelTests.makeModel(fetch: fetch)
                let result = try await model.doGenerate(options: .init(prompt: DeepInfraImageModelTests.prompt, n: 1))

                #expect(result.response.headers?["content-length"] == "52")
                #expect(result.response.headers?["x-request-id"] == "test-request-id")
                #expect(result.response.headers?["content-type"] == "application/json")
            }
        }
    }

    @Test("constructor exposes correct provider and model information")
    func constructorExposesCorrectProviderAndModelInformation() throws {
        let model = Self.makeModel(provider: "deepinfra", baseURL: "https://api.example.com")

        #expect(model.provider == "deepinfra")
        #expect(model.modelId == "stability-ai/sdxl")
        #expect(model.specificationVersion == "v3")

        switch model.maxImagesPerCall {
        case .value(let value):
            #expect(value == 1)
        default:
            Issue.record("Expected maxImagesPerCall to be .value(1)")
        }
    }

    @Suite("Image Editing", .serialized)
    struct ImageEditingTests {
        private func makeEditModel(fetch: FetchFunction? = nil, currentDate: @escaping @Sendable () -> Date = { Date() }) -> DeepInfraImageModel {
            DeepInfraImageModel(
                modelId: "black-forest-labs/FLUX.1-Kontext-dev",
                config: DeepInfraImageModelConfig(
                    provider: "deepinfra",
                    baseURL: "https://edit.example.com/inference",
                    headers: { ["api-key": "test-key"] },
                    fetch: fetch,
                    currentDate: currentDate
                )
            )
        }

        private func httpResponse(
            url: URL,
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "application/json"]
        ) -> HTTPURLResponse {
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
        }

        private func editResponseBody() throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "created": 1_234_567_890,
                "data": [
                    ["b64_json": "edited-image-base64"],
                ],
            ])
        }

        private func countOccurrences(_ needle: String, in haystack: String) -> Int {
            haystack.components(separatedBy: needle).count - 1
        }

        @Test("sends edit request with files")
        func sendsEditRequestWithFiles() async throws {
            actor Capture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let capture = Capture()
            let url = URL(string: "https://edit.example.com/openai/images/edits")!
            let responseData = try editResponseBody()

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: self.httpResponse(url: url))
            }

            let model = makeEditModel(fetch: fetch)
            let input: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)

            let result = try await model.doGenerate(options: .init(
                prompt: "Turn the cat into a dog",
                n: 1,
                size: "1024x1024",
                providerOptions: [:],
                files: [input]
            ))

            guard case let .base64(images) = result.images else {
                Issue.record("Expected base64 images")
                return
            }
            #expect(images == ["edited-image-base64"])
            #expect(await capture.value()?.url?.absoluteString == "https://edit.example.com/openai/images/edits")

            guard let request = await capture.value() else { return }
            let headers = request.allHTTPHeaderFields ?? [:]
            let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            let contentType = normalized["content-type"] ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        }

        @Test("sends edit request with files and mask")
        func sendsEditRequestWithFilesAndMask() async throws {
            actor Capture {
                var body: Data?
                func store(_ data: Data?) { body = data }
                func value() -> Data? { body }
            }

            let capture = Capture()
            let url = URL(string: "https://edit.example.com/openai/images/edits")!
            let responseData = try editResponseBody()

            let fetch: FetchFunction = { request in
                await capture.store(request.httpBody)
                return FetchResponse(body: .data(responseData), urlResponse: self.httpResponse(url: url))
            }

            let model = makeEditModel(fetch: fetch)
            let input: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)
            let mask: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([255, 255, 255, 0])), providerOptions: nil)

            let result = try await model.doGenerate(options: .init(
                prompt: "Add a flamingo to the pool",
                n: 1,
                providerOptions: [:],
                files: [input],
                mask: mask
            ))

            guard case let .base64(images) = result.images else {
                Issue.record("Expected base64 images")
                return
            }
            #expect(images == ["edited-image-base64"])

            guard let body = await capture.value() else {
                Issue.record("Expected multipart body")
                return
            }
            let bodyString = String(decoding: body, as: UTF8.self)
            #expect(bodyString.contains("name=\"mask\""))
            #expect(bodyString.contains("filename=\"mask.png\""))
        }

        @Test("sends edit request with multiple images")
        func sendsEditRequestWithMultipleImages() async throws {
            actor Capture {
                var body: Data?
                func store(_ data: Data?) { body = data }
                func value() -> Data? { body }
            }

            let capture = Capture()
            let url = URL(string: "https://edit.example.com/openai/images/edits")!
            let responseData = try editResponseBody()

            let fetch: FetchFunction = { request in
                await capture.store(request.httpBody)
                return FetchResponse(body: .data(responseData), urlResponse: self.httpResponse(url: url))
            }

            let model = makeEditModel(fetch: fetch)
            let image1: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)
            let image2: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)

            _ = try await model.doGenerate(options: .init(
                prompt: "Combine these images",
                n: 1,
                providerOptions: [:],
                files: [image1, image2]
            ))

            guard let body = await capture.value() else {
                Issue.record("Expected multipart body")
                return
            }
            let bodyString = String(decoding: body, as: UTF8.self)
            #expect(countOccurrences("name=\"image\"", in: bodyString) == 2)
        }

        @Test("includes response metadata for edit requests")
        func includesResponseMetadataForEditRequests() async throws {
            let testDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
            let url = URL(string: "https://edit.example.com/openai/images/edits")!
            let responseData = try editResponseBody()

            let fetch: FetchFunction = { _ in
                FetchResponse(body: .data(responseData), urlResponse: self.httpResponse(url: url))
            }

            let model = makeEditModel(fetch: fetch, currentDate: { testDate })
            let input: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)

            let result = try await model.doGenerate(options: .init(
                prompt: "Edit this image",
                n: 1,
                providerOptions: [:],
                files: [input]
            ))

            #expect(result.response.timestamp == testDate)
            #expect(result.response.modelId == "black-forest-labs/FLUX.1-Kontext-dev")
            #expect(result.response.headers?.isEmpty == false)
        }

        @Test("passes provider options in edit request")
        func passesProviderOptionsInEditRequest() async throws {
            actor Capture {
                var body: Data?
                func store(_ data: Data?) { body = data }
                func value() -> Data? { body }
            }

            let capture = Capture()
            let url = URL(string: "https://edit.example.com/openai/images/edits")!
            let responseData = try editResponseBody()

            let fetch: FetchFunction = { request in
                await capture.store(request.httpBody)
                return FetchResponse(body: .data(responseData), urlResponse: self.httpResponse(url: url))
            }

            let model = makeEditModel(fetch: fetch)
            let input: ImageModelV3File = .file(mediaType: "image/png", data: .binary(Data([137, 80, 78, 71])), providerOptions: nil)

            _ = try await model.doGenerate(options: .init(
                prompt: "Edit with custom options",
                n: 1,
                providerOptions: ["deepinfra": ["guidance": .number(7.5)]],
                files: [input]
            ))

            guard let body = await capture.value() else {
                Issue.record("Expected multipart body")
                return
            }
            let bodyString = String(decoding: body, as: UTF8.self)
            #expect(bodyString.contains("name=\"guidance\""))
            #expect(bodyString.contains("7.5"))
        }
    }
}
