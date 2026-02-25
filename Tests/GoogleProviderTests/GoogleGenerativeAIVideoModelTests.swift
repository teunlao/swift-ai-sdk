import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

@Suite("GoogleGenerativeAIVideoModel")
struct GoogleGenerativeAIVideoModelTests {
    private let prompt = "A futuristic city with flying cars"

    private func makeModel(
        modelId: GoogleGenerativeAIVideoModelId = .veo31GeneratePreview,
        apiKey: String = "test-api-key",
        fetch: @escaping FetchFunction,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> GoogleGenerativeAIVideoModel {
        GoogleGenerativeAIVideoModel(
            modelId: modelId,
            config: GoogleGenerativeAIVideoModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: { ["x-goog-api-key": apiKey] },
                fetch: fetch,
                generateId: generateID,
                currentDate: currentDate
            )
        )
    }

    private func makeOptions(
        prompt: String? = "A futuristic city with flying cars",
        n: Int = 1,
        image: VideoModelV3File? = nil,
        aspectRatio: String? = nil,
        resolution: String? = nil,
        duration: Int? = nil,
        seed: Int? = nil,
        providerOptions: SharedV3ProviderOptions = ["google": ["pollIntervalMs": .number(10)]],
        abortSignal: (@Sendable () -> Bool)? = nil
    ) -> VideoModelV3CallOptions {
        VideoModelV3CallOptions(
            prompt: prompt,
            n: n,
            aspectRatio: aspectRatio,
            resolution: resolution,
            duration: duration,
            seed: seed,
            image: image,
            providerOptions: providerOptions,
            abortSignal: abortSignal
        )
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func httpResponse(url: URL, statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Test("constructor exposes provider/model/specification/maxVideos")
    func constructorInfo() async throws {
        let fetch: FetchFunction = { request in
            let body = try self.jsonData([
                "name": "operations/test-op",
                "done": true,
                "response": [
                    "generateVideoResponse": [
                        "generatedSamples": [
                            ["video": ["uri": "https://example.com/video.mp4"]]
                        ]
                    ]
                ]
            ])
            return FetchResponse(
                body: .data(body),
                urlResponse: self.httpResponse(url: try #require(request.url))
            )
        }

        let model = makeModel(fetch: fetch)

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "veo-3.1-generate-preview")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 4)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 4")
        }
    }

    @Test("constructor supports different model IDs")
    func constructorSupportsDifferentModelIDs() async throws {
        let fetch: FetchFunction = { request in
            let body = try self.jsonData([
                "name": "operations/test-op",
                "done": true,
                "response": [
                    "generateVideoResponse": [
                        "generatedSamples": [
                            ["video": ["uri": "https://example.com/video.mp4"]]
                        ]
                    ]
                ]
            ])
            return FetchResponse(
                body: .data(body),
                urlResponse: self.httpResponse(url: try #require(request.url))
            )
        }

        let model = makeModel(modelId: .veo31Generate, fetch: fetch)
        #expect(model.modelId == "veo-3.1-generate")
    }

    @Test("doGenerate maps prompt/seed/aspectRatio/resolution/duration")
    func requestMappingCoreFields() async throws {
        actor Capture {
            var predictBody: JSONValue?
            func set(_ body: JSONValue) { predictBody = body }
            func value() -> JSONValue? { predictBody }
        }

        let capture = Capture()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    await capture.set(json)
                }

                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: makeOptions(
            prompt: prompt,
            aspectRatio: "16:9",
            resolution: "1920x1080",
            duration: 5,
            seed: 42
        ))

        #expect(await capture.value() == .object([
            "instances": .array([.object(["prompt": .string(prompt)])]),
            "parameters": .object([
                "sampleCount": .number(1),
                "seed": .number(42),
                "aspectRatio": .string("16:9"),
                "resolution": .string("1080p"),
                "durationSeconds": .number(5)
            ])
        ]))
    }

    @Test("doGenerate maps n to sampleCount and returns multiple videos")
    func sampleCountAndMultipleVideos() async throws {
        actor Capture {
            var predictBody: JSONValue?
            func set(_ body: JSONValue) { predictBody = body }
            func value() -> JSONValue? { predictBody }
        }

        let capture = Capture()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    await capture.set(json)
                }

                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video1.mp4"]],
                                ["video": ["uri": "https://example.com/video2.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions(
            n: 2
        ))

        #expect(await capture.value() == .object([
            "instances": .array([.object(["prompt": .string(prompt)])]),
            "parameters": .object([
                "sampleCount": .number(2)
            ])
        ]))

        #expect(result.videos.count == 2)
        #expect(result.videos[0] == .url(url: "https://example.com/video1.mp4?key=test-api-key", mediaType: "video/mp4"))
        #expect(result.videos[1] == .url(url: "https://example.com/video2.mp4?key=test-api-key", mediaType: "video/mp4"))
    }

    @Test("doGenerate returns empty warnings array when no warnings are produced")
    func emptyWarningsArray() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions())
        #expect(result.warnings == [])
    }

    @Test("doGenerate maps provider options and passthrough values")
    func providerOptionsMapping() async throws {
        actor Capture {
            var predictBody: JSONValue?
            func set(_ body: JSONValue) { predictBody = body }
            func value() -> JSONValue? { predictBody }
        }

        let capture = Capture()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    await capture.set(json)
                }

                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: makeOptions(
            providerOptions: [
                "google": [
                    "pollIntervalMs": .number(10),
                    "personGeneration": .string("allow_adult"),
                    "negativePrompt": .string("blurry, low quality"),
                    "customOption": .string("custom-value"),
                    "referenceImages": .array([
                        .object(["bytesBase64Encoded": .string("reference-image-data")]),
                        .object(["gcsUri": .string("gs://bucket/reference.png")])
                    ])
                ]
            ]
        ))

        #expect(await capture.value() == .object([
            "instances": .array([
                .object([
                    "prompt": .string(prompt),
                    "referenceImages": .array([
                        .object([
                            "inlineData": .object([
                                "mimeType": .string("image/png"),
                                "data": .string("reference-image-data")
                            ])
                        ]),
                        .object([
                            "gcsUri": .string("gs://bucket/reference.png")
                        ])
                    ])
                ])
            ]),
            "parameters": .object([
                "sampleCount": .number(1),
                "personGeneration": .string("allow_adult"),
                "negativePrompt": .string("blurry, low quality"),
                "customOption": .string("custom-value")
            ])
        ]))
    }

    @Test("doGenerate prefers gcsUri reference image when bytes are empty")
    func referenceImagePrefersGCSWhenBytesEmpty() async throws {
        actor Capture {
            var predictBody: JSONValue?
            func set(_ body: JSONValue) { predictBody = body }
            func value() -> JSONValue? { predictBody }
        }

        let capture = Capture()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    await capture.set(json)
                }

                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: makeOptions(
            providerOptions: [
                "google": [
                    "pollIntervalMs": .number(10),
                    "referenceImages": .array([
                        .object([
                            "bytesBase64Encoded": .string(""),
                            "gcsUri": .string("gs://bucket/reference.png")
                        ])
                    ])
                ]
            ]
        ))

        #expect(await capture.value() == .object([
            "instances": .array([
                .object([
                    "prompt": .string(prompt),
                    "referenceImages": .array([
                        .object([
                            "gcsUri": .string("gs://bucket/reference.png")
                        ])
                    ])
                ])
            ]),
            "parameters": .object([
                "sampleCount": .number(1)
            ])
        ]))
    }

    @Test("doGenerate accepts decimal poll options")
    func decimalPollOptionsAreAccepted() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions(
            providerOptions: [
                "google": [
                    "pollIntervalMs": .number(10.5),
                    "pollTimeoutMs": .number(500.5)
                ]
            ]
        ))

        #expect(!result.videos.isEmpty)
    }

    @Test("doGenerate sends file image as inlineData")
    func imageToVideoInlineData() async throws {
        actor Capture {
            var predictBody: JSONValue?
            func set(_ body: JSONValue) { predictBody = body }
            func value() -> JSONValue? { predictBody }
        }

        let capture = Capture()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    await capture.set(json)
                }

                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: makeOptions(
            image: .file(mediaType: "image/png", data: .base64("base64-image-data"), providerOptions: nil)
        ))

        #expect(await capture.value() == .object([
            "instances": .array([
                .object([
                    "prompt": .string(prompt),
                    "image": .object([
                        "inlineData": .object([
                            "mimeType": .string("image/png"),
                            "data": .string("base64-image-data")
                        ])
                    ])
                ])
            ]),
            "parameters": .object([
                "sampleCount": .number(1)
            ])
        ]))
    }

    @Test("doGenerate warns for URL image input")
    func urlImageWarning() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions(
            image: .url(url: "https://example.com/image.png", providerOptions: nil)
        ))

        #expect(result.warnings == [
            .unsupported(
                feature: "URL-based image input",
                details: "Google Generative AI video models require base64-encoded images. URL will be ignored."
            )
        ])
    }

    @Test("doGenerate appends API key to video URL")
    func appendApiKeyToVideoURL() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://generativelanguage.googleapis.com/files/video-123.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions())

        #expect(result.videos.first == VideoModelV3VideoData.url(
            url: "https://generativelanguage.googleapis.com/files/video-123.mp4?key=test-api-key",
            mediaType: "video/mp4"
        ))
    }

    @Test("doGenerate appends API key with ampersand when URL contains query params")
    func appendApiKeyWithAmpersand() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://generativelanguage.googleapis.com/files/video-123.mp4?param=value"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions())

        #expect(result.videos.first == VideoModelV3VideoData.url(
            url: "https://generativelanguage.googleapis.com/files/video-123.mp4?param=value&key=test-api-key",
            mediaType: "video/mp4"
        ))
    }

    @Test("doGenerate includes response and provider metadata")
    func responseAndProviderMetadata() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_704_067_200)
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(
                        url: request.url!,
                        headers: [
                            "Content-Type": "application/json",
                            "x-request-id": "req-123"
                        ]
                    )
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch, currentDate: { timestamp })
        let result = try await model.doGenerate(options: makeOptions())

        #expect(result.response.timestamp == timestamp)
        #expect(result.response.modelId == "veo-3.1-generate-preview")
        #expect(result.providerMetadata == [
            "google": [
                "videos": .array([
                    .object([
                        "uri": .string("https://example.com/video.mp4")
                    ])
                ])
            ]
        ])
    }

    @Test("doGenerate throws when operation name is missing")
    func errorNoOperationName() async throws {
        let fetch: FetchFunction = { request in
            let response = try self.jsonData([
                "done": false
            ])
            return FetchResponse(
                body: .data(response),
                urlResponse: self.httpResponse(url: try #require(request.url))
            )
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions())
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message == "No operation name returned from API")
        }
    }

    @Test("doGenerate throws when operation fails")
    func errorOperationFailed() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "error": [
                        "code": 400,
                        "message": "Invalid request",
                        "status": "INVALID_ARGUMENT"
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions())
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("Invalid request"))
        }
    }

    @Test("doGenerate throws when no videos are returned")
    func errorNoVideos() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": []
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions())
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("No videos in response"))
        }
    }

    @Test("doGenerate throws when generated sample URI is empty")
    func errorEmptyGeneratedSampleURI() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": ""]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions())
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message == "No valid videos in response")
        }
    }

    @Test("doGenerate polls until operation is done")
    func pollingUntilDone() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() -> Int {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value
            }

            func current() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let pollCounter = Counter()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/poll-test",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/poll-test") {
                let current = pollCounter.increment()
                if current < 3 {
                    let response = try self.jsonData([
                        "name": "operations/poll-test",
                        "done": false
                    ])
                    return FetchResponse(
                        body: .data(response),
                        urlResponse: self.httpResponse(url: request.url!)
                    )
                }

                let response = try self.jsonData([
                    "name": "operations/poll-test",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/final-video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(apiKey: "test-key", fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions(
            providerOptions: [
                "google": [
                    "pollIntervalMs": .number(10)
                ]
            ]
        ))

        #expect(pollCounter.current() == 3)
        #expect(result.videos.first == VideoModelV3VideoData.url(
            url: "https://example.com/final-video.mp4?key=test-key",
            mediaType: "video/mp4"
        ))
    }

    @Test("doGenerate re-resolves headers for polling requests")
    func dynamicHeadersUsedForPolling() async throws {
        actor Capture {
            var requestHeaders: [[String: String]] = []
            func append(_ headers: [String: String]) { requestHeaders.append(headers) }
            func values() -> [[String: String]] { requestHeaders }
        }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value
            }
        }

        let capture = Capture()
        let headerCounter = Counter()
        let fetch: FetchFunction = { request in
            await capture.append(request.allHTTPHeaderFields ?? [:])
            let urlString = request.url!.absoluteString

            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = GoogleGenerativeAIVideoModel(
            modelId: .veo31GeneratePreview,
            config: GoogleGenerativeAIVideoModelConfig(
                provider: "google.generative-ai",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                headers: {
                    ["x-goog-api-key": "dynamic-\(headerCounter.next())"]
                },
                fetch: fetch,
                generateId: generateID
            )
        )

        _ = try await model.doGenerate(options: makeOptions(
            providerOptions: ["google": ["pollIntervalMs": .number(10)]]
        ))

        let headers = await capture.values()
        #expect(headers.count >= 2)

        func value(_ name: String, from headers: [String: String]) -> String? {
            headers.first(where: { $0.key.lowercased() == name.lowercased() })?.value
        }

        let firstRequestKey = value("x-goog-api-key", from: headers[0])
        let secondRequestKey = value("x-goog-api-key", from: headers[1])
        #expect(firstRequestKey == "dynamic-1")
        #expect(secondRequestKey == "dynamic-2")
    }

    @Test("doGenerate times out after pollTimeoutMs")
    func pollingTimeout() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/timeout-test",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/timeout-test") {
                let response = try self.jsonData([
                    "name": "operations/timeout-test",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions(
                providerOptions: [
                    "google": [
                        "pollIntervalMs": .number(10),
                        "pollTimeoutMs": .number(50)
                    ]
                ]
            ))
            Issue.record("Expected timeout error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("timed out"))
        }
    }

    @Test("doGenerate respects abort signal")
    func pollingAbort() async throws {
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var aborted = false

            func abort() {
                lock.lock()
                defer { lock.unlock() }
                aborted = true
            }

            func isAborted() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return aborted
            }
        }

        let flag = Flag()
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/abort-test",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/abort-test") {
                Task {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    flag.abort()
                }
                let response = try self.jsonData([
                    "name": "operations/abort-test",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: makeOptions(
                providerOptions: [
                    "google": [
                        "pollIntervalMs": .number(100)
                    ]
                ],
                abortSignal: { flag.isAborted() }
            ))
            Issue.record("Expected abort error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("aborted"))
        }
    }

    @Test("doGenerate always returns video/mp4 media type")
    func mediaTypeIsAlwaysMp4() async throws {
        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString.contains(":predictLongRunning") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": false
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            if urlString.contains("/operations/test-op") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "generateVideoResponse": [
                            "generatedSamples": [
                                ["video": ["uri": "https://example.com/video.mp4"]]
                            ]
                        ]
                    ]
                ])
                return FetchResponse(
                    body: .data(response),
                    urlResponse: self.httpResponse(url: request.url!)
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: makeOptions())

        guard case let .url(_, mediaType)? = result.videos.first else {
            Issue.record("Expected URL video")
            return
        }
        #expect(mediaType == "video/mp4")
    }
}
