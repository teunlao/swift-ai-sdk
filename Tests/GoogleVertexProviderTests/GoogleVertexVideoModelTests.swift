import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexVideoModel")
struct GoogleVertexVideoModelTests {
    private let prompt = "A futuristic city with flying cars"

    private func makeModel(
        modelId: GoogleVertexVideoModelId = .veo20Generate001,
        fetch: @escaping FetchFunction,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> GoogleVertexVideoModel {
        GoogleVertexVideoModel(
            modelId: modelId,
            config: GoogleVertexVideoModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["api-key": "test-key"] },
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
        providerOptions: SharedV3ProviderOptions = ["vertex": ["pollIntervalMs": .number(10)]],
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
                    "videos": [
                        [
                            "bytesBase64Encoded": "video-data",
                            "mimeType": "video/mp4"
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

        #expect(model.provider == "google-vertex")
        #expect(model.modelId == "veo-2.0-generate-001")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 4)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 4")
        }
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
                "vertex": [
                    "pollIntervalMs": .number(10),
                    "personGeneration": .string("allow_adult"),
                    "negativePrompt": .string("blurry, low quality"),
                    "generateAudio": .bool(true),
                    "gcsOutputDirectory": .string("gs://bucket/output/"),
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
                            "bytesBase64Encoded": .string("reference-image-data")
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
                "generateAudio": .bool(true),
                "gcsOutputDirectory": .string("gs://bucket/output/"),
                "customOption": .string("custom-value")
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
                "vertex": [
                    "pollIntervalMs": .number(10.5),
                    "pollTimeoutMs": .number(500.5)
                ]
            ]
        ))

        #expect(!result.videos.isEmpty)
    }

    @Test("doGenerate sends file image as bytesBase64Encoded")
    func imageToVideoBytesBase64() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
                        "bytesBase64Encoded": .string("base64-image-data"),
                        "mimeType": .string("image/png")
                    ])
                ])
            ]),
            "parameters": .object([
                "sampleCount": .number(1)
            ])
        ]))
    }

    @Test("doGenerate omits empty mimeType for image payload")
    func imageToVideoOmitsEmptyMimeType() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
            image: .file(mediaType: "", data: .base64("base64-image-data"), providerOptions: nil)
        ))

        #expect(await capture.value() == .object([
            "instances": .array([
                .object([
                    "prompt": .string(prompt),
                    "image": .object([
                        "bytesBase64Encoded": .string("base64-image-data")
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
                details: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."
            )
        ])
    }

    @Test("doGenerate returns base64 videos and metadata")
    func returnsBase64Video() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "base64-video-data",
                                "mimeType": "video/mp4"
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

        #expect(result.videos.first == .base64(data: "base64-video-data", mediaType: "video/mp4"))
        #expect(result.providerMetadata == [
            "google-vertex": [
                "videos": .array([
                    .object([
                        "mimeType": .string("video/mp4")
                    ])
                ])
            ]
        ])
    }

    @Test("doGenerate returns GCS URI videos and metadata")
    func returnsGCSURIVideo() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "gcsUri": "gs://bucket/video.mp4",
                                "mimeType": "video/mp4"
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

        #expect(result.videos.first == .url(url: "gs://bucket/video.mp4", mediaType: "video/mp4"))
        #expect(result.providerMetadata == [
            "google-vertex": [
                "videos": .array([
                    .object([
                        "gcsUri": .string("gs://bucket/video.mp4"),
                        "mimeType": .string("video/mp4")
                    ])
                ])
            ]
        ])
    }

    @Test("doGenerate includes response timestamp/modelId")
    func responseMetadata() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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
        #expect(result.response.modelId == "veo-2.0-generate-001")
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

            if urlString.contains(":fetchPredictOperation") {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": []
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

        actor PollCapture {
            var operationNames: [String] = []
            func append(_ operationName: String) {
                operationNames.append(operationName)
            }
            func values() -> [String] { operationNames }
        }

        let pollCounter = Counter()
        let pollCapture = PollCapture()

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

            if urlString.contains(":fetchPredictOperation") {
                if let body = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: body)
                    if case .object(let dict) = json,
                       case .string(let operationName)? = dict["operationName"] {
                        await pollCapture.append(operationName)
                    }
                }

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
                        "videos": [
                            [
                                "bytesBase64Encoded": "final-video",
                                "mimeType": "video/mp4"
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
                "vertex": [
                    "pollIntervalMs": .number(10)
                ]
            ]
        ))

        #expect(pollCounter.current() == 3)
        #expect(await pollCapture.values() == ["operations/poll-test", "operations/poll-test", "operations/poll-test"])
        #expect(result.videos.first == .base64(data: "final-video", mediaType: "video/mp4"))
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": "video/mp4"
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

        let model = GoogleVertexVideoModel(
            modelId: .veo20Generate001,
            config: GoogleVertexVideoModelConfig(
                provider: "google-vertex",
                baseURL: "https://api.example.com",
                headers: { ["x-test-token": "dynamic-\(headerCounter.next())"] },
                fetch: fetch,
                generateId: generateID
            )
        )

        _ = try await model.doGenerate(options: makeOptions(
            providerOptions: ["vertex": ["pollIntervalMs": .number(10)]]
        ))

        let headers = await capture.values()
        #expect(headers.count >= 2)

        func value(_ name: String, from headers: [String: String]) -> String? {
            headers.first(where: { $0.key.lowercased() == name.lowercased() })?.value
        }

        let firstRequestToken = value("x-test-token", from: headers[0])
        let secondRequestToken = value("x-test-token", from: headers[1])
        #expect(firstRequestToken == "dynamic-1")
        #expect(secondRequestToken == "dynamic-2")
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

            if urlString.contains(":fetchPredictOperation") {
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
                    "vertex": [
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

            if urlString.contains(":fetchPredictOperation") {
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
                    "vertex": [
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

    @Test("doGenerate defaults media type to video/mp4 when mimeType missing")
    func defaultMediaType() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data"
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

        #expect(result.videos.first == .base64(data: "video-data", mediaType: "video/mp4"))
    }

    @Test("doGenerate defaults media type to video/mp4 when mimeType is empty")
    func defaultMediaTypeWhenMimeTypeEmpty() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "video-data",
                                "mimeType": ""
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

        #expect(result.videos.first == .base64(data: "video-data", mediaType: "video/mp4"))
        #expect(result.providerMetadata == [
            "google-vertex": [
                "videos": .array([
                    .object([
                        "mimeType": .string("")
                    ])
                ])
            ]
        ])
    }

    @Test("doGenerate prefers gcsUri when bytesBase64Encoded is empty")
    func prefersGCSURIWhenBase64Empty() async throws {
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

            if urlString.contains(":fetchPredictOperation") {
                let response = try self.jsonData([
                    "name": "operations/test-op",
                    "done": true,
                    "response": [
                        "videos": [
                            [
                                "bytesBase64Encoded": "",
                                "gcsUri": "gs://bucket/video.mp4",
                                "mimeType": "video/mp4"
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

        #expect(result.videos.first == .url(url: "gs://bucket/video.mp4", mediaType: "video/mp4"))
    }
}
