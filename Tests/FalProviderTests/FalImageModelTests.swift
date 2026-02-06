import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalImageModel")
struct FalImageModelTests {
    private let modelId: FalImageModelId = "fal-ai/qwen-image"
    private let prompt = "A cute baby sea otter"
    private let imageURL = "https://api.example.com/image.png"

    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func first() -> URLRequest? { requests.first }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func makeModel(
        headers: @escaping @Sendable () -> [String: String?] = { ["api-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) }
    ) -> FalImageModel {
        FalImageModel(
            modelId: modelId,
            config: FalImageModelConfig(
                provider: "fal.image",
                baseURL: "https://api.example.com",
                headers: headers,
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func decodeRequestBodyJSON(_ request: URLRequest) throws -> JSONValue {
        guard let body = request.httpBody else {
            throw NSError(domain: "FalImageModelTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing request body"])
        }
        return try JSONDecoder().decode(JSONValue.self, from: body)
    }

    private func makeSuccessfulFetch(
        capture: RequestCapture,
        postResponseBody: Any? = nil
    ) throws -> FetchFunction {
        let postURL = "https://api.example.com/\(modelId.rawValue)"
        let resolvedPostBody = postResponseBody ?? [
            "images": [
                [
                    "url": imageURL,
                    "width": 1024,
                    "height": 1024,
                    "content_type": "image/png"
                ]
            ]
        ]
        let postData = try jsonData(resolvedPostBody)
        let imageData = Data("binary-image-data".utf8)

        return { request in
            let url = request.url?.absoluteString ?? ""
            if url == postURL {
                await capture.append(request)
                return FetchResponse(
                    body: .data(postData),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/json",
                            "x-request-id": "image-request-id"
                        ]
                    )
                )
            }

            if url == self.imageURL {
                return FetchResponse(
                    body: .data(imageData),
                    urlResponse: makeHTTPResponse(
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

    @Test("passes size, prompt and seed")
    func passesSizePromptAndSeed() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            seed: 123,
            providerOptions: [:]
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "prompt": .string(prompt),
            "seed": .number(123),
            "image_size": .object([
                "width": .number(1024),
                "height": .number(1024)
            ]),
            "num_images": .number(1)
        ]))
    }

    @Test("maps camelCase provider options to API snake_case keys")
    func mapsCamelCaseProviderOptions() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "fal": [
                    "imageUrl": .string("https://example.com/image.png"),
                    "guidanceScale": .number(7.5),
                    "numInferenceSteps": .number(50),
                    "enableSafetyChecker": .bool(false)
                ]
            ]
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "prompt": .string(prompt),
            "num_images": .number(1),
            "image_url": .string("https://example.com/image.png"),
            "guidance_scale": .number(7.5),
            "num_inference_steps": .number(50),
            "enable_safety_checker": .bool(false)
        ]))
    }

    @Test("validates provider options schema")
    func validatesProviderOptionsSchema() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "fal": [
                        "guidanceScale": .number(0)
                    ]
                ]
            ))
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid fal provider options")
        }
    }

    @Test("accepts deprecated snake_case provider options with warning")
    func acceptsDeprecatedSnakeCaseOptions() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [
                "fal": [
                    "image_url": .string("https://example.com/image.png"),
                    "guidance_scale": .number(7.5),
                    "num_inference_steps": .number(50)
                ]
            ]
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "prompt": .string(prompt),
            "num_images": .number(1),
            "image_url": .string("https://example.com/image.png"),
            "guidance_scale": .number(7.5),
            "num_inference_steps": .number(50)
        ]))

        #expect(result.warnings.count == 1)
        guard case .other(let warningMessage) = result.warnings[0] else {
            Issue.record("Expected .other warning")
            return
        }
        #expect(warningMessage.contains("deprecated snake_case"))
        #expect(warningMessage.contains("'image_url' (use 'imageUrl')"))
        #expect(warningMessage.contains("'guidance_scale' (use 'guidanceScale')"))
        #expect(warningMessage.contains("'num_inference_steps' (use 'numInferenceSteps')"))
    }

    @Test("handles image API validation errors")
    func handlesImageValidationErrors() async throws {
        let postURL = "https://api.example.com/\(modelId.rawValue)"
        let errorBody = try jsonData([
            "detail": [
                [
                    "loc": ["prompt"],
                    "msg": "Invalid prompt",
                    "type": "value_error"
                ]
            ]
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == postURL {
                return FetchResponse(
                    body: .data(errorBody),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 400,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "prompt: Invalid prompt")
            #expect(error.statusCode == 400)
            #expect(error.url == postURL)
        }
    }

    @Test("handles image API errors using fal error envelope")
    func handlesFalErrorEnvelope() async throws {
        let postURL = "https://api.example.com/\(modelId.rawValue)"
        let errorBody = try jsonData([
            "error": [
                "message": "Something went wrong",
                "code": 400
            ]
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == postURL {
                return FetchResponse(
                    body: .data(errorBody),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 400,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "Something went wrong")
            #expect(error.statusCode == 400)
            #expect(error.url == postURL)
        }
    }

    @Test("handles image API errors with message field")
    func handlesImageMessageErrors() async throws {
        let postURL = "https://api.example.com/\(modelId.rawValue)"
        let errorBody = try jsonData([
            "message": "Something went wrong"
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == postURL {
                return FetchResponse(
                    body: .data(errorBody),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 400,
                        headers: ["Content-Type": "application/json"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: .init(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected APICallError")
        } catch let error as APICallError {
            #expect(error.message == "Something went wrong")
            #expect(error.statusCode == 400)
            #expect(error.url == postURL)
        }
    }

    @Test("supports image editing with file and mask data URI")
    func supportsImageEditingWithMask() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)

        let imageData = Data([137, 80, 78, 71])
        let maskData = Data([255, 255, 255, 0])

        _ = try await model.doGenerate(options: .init(
            prompt: "Add a flamingo to the pool",
            n: 1,
            providerOptions: [:],
            files: [.file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil)],
            mask: .file(mediaType: "image/png", data: .binary(maskData), providerOptions: nil)
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }

        let body = try decodeRequestBodyJSON(request)
        #expect(body == .object([
            "prompt": .string("Add a flamingo to the pool"),
            "image_url": .string("data:image/png;base64,iVBORw=="),
            "mask_url": .string("data:image/png;base64,////AA=="),
            "num_images": .number(1)
        ]))
    }

    @Test("warns on multiple files when useMultipleImages is disabled")
    func warnsOnMultipleFilesWithoutUseMultipleImages() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)
        let imageData = Data([137, 80, 78, 71])

        let result = try await model.doGenerate(options: .init(
            prompt: "Edit images",
            n: 1,
            providerOptions: [:],
            files: [
                .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil),
                .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil)
            ]
        ))

        #expect(result.warnings.count == 1)
        guard case .other(let warningMessage) = result.warnings[0] else {
            Issue.record("Expected .other warning")
            return
        }
        #expect(warningMessage.contains("useMultipleImages is not enabled"))

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }
        let body = try decodeRequestBodyJSON(request)
        if case .object(let object) = body {
            #expect(object["image_url"] == .string("data:image/png;base64,iVBORw=="))
            #expect(object["image_urls"] == nil)
        } else {
            Issue.record("Expected JSON object body")
        }
    }

    @Test("sends image_urls when useMultipleImages is true")
    func sendsImageUrlsWhenUseMultipleImagesEnabled() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let model = makeModel(fetch: fetch)
        let imageData = Data([137, 80, 78, 71])

        let result = try await model.doGenerate(options: .init(
            prompt: "Edit these images",
            n: 1,
            providerOptions: [
                "fal": [
                    "useMultipleImages": .bool(true)
                ]
            ],
            files: [
                .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil),
                .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil)
            ]
        ))

        #expect(result.warnings.isEmpty)

        guard let request = await capture.first() else {
            Issue.record("Missing request capture")
            return
        }
        let body = try decodeRequestBodyJSON(request)
        if case .object(let object) = body {
            #expect(object["image_urls"] == .array([
                .string("data:image/png;base64,iVBORw=="),
                .string("data:image/png;base64,iVBORw==")
            ]))
            #expect(object["image_url"] == nil)
        } else {
            Issue.record("Expected JSON object body")
        }
    }

    @Test("parses single-image response and preserves null metadata fields")
    func parsesSingleImageResponseAndPreservesNulls() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(
            capture: capture,
            postResponseBody: [
                "image": [
                    "url": imageURL,
                    "content_type": "image/png",
                    "file_name": NSNull(),
                    "file_size": NSNull(),
                    "width": NSNull(),
                    "height": NSNull()
                ],
                "description": "response with nullable dimensions",
                "has_nsfw_concepts": [false]
            ]
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

        guard let falMetadata = result.providerMetadata?["fal"] else {
            Issue.record("Missing fal provider metadata")
            return
        }
        #expect(falMetadata.images.count == 1)

        guard case .object(let imageMetadata) = falMetadata.images[0] else {
            Issue.record("Expected image metadata object")
            return
        }
        #expect(imageMetadata["contentType"] == .string("image/png"))
        #expect(imageMetadata["fileName"] == .null)
        #expect(imageMetadata["fileSize"] == .null)
        #expect(imageMetadata["width"] == .null)
        #expect(imageMetadata["height"] == .null)
        #expect(imageMetadata["nsfw"] == .bool(false))

        guard let additionalData = falMetadata.additionalData, case .object(let rootMetadata) = additionalData else {
            Issue.record("Missing additional metadata")
            return
        }
        #expect(rootMetadata["description"] == .string("response with nullable dimensions"))
    }

    @Test("includes timestamp, modelId and headers in response metadata")
    func includesResponseMetadata() async throws {
        let capture = RequestCapture()
        let fetch = try makeSuccessfulFetch(capture: capture)
        let testDate = Date(timeIntervalSince1970: 0)
        let model = makeModel(fetch: fetch, currentDate: { testDate })

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            n: 1,
            providerOptions: [:]
        ))

        #expect(result.response.timestamp == testDate)
        #expect(result.response.modelId == modelId.rawValue)
        #expect(result.response.headers?["x-request-id"] == "image-request-id")
    }
}
