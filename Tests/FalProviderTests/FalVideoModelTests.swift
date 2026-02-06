import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalVideoModel")
struct FalVideoModelTests {
    private let prompt = "A futuristic city with flying cars"

    private func makeModel(
        modelId: FalVideoModelId = "luma-dream-machine",
        headers: (@Sendable () -> [String: String?])? = { ["api-key": "test-key"] },
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_704_067_200) } // 2024-01-01
    ) -> FalVideoModel {
        FalVideoModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.video",
                url: { options in options.path },
                headers: headers ?? { [:] },
                fetch: fetch,
                currentDate: currentDate
            )
        )
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func httpResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Test("constructor exposes correct provider and model information")
    func constructorInfo() async throws {
        let model = makeModel()

        #expect(model.provider == "fal.video")
        #expect(model.modelId == "luma-dream-machine")
        #expect(model.specificationVersion == "v3")

        switch model.maxVideosPerCall {
        case .value(let value):
            #expect(value == 1)
        case .default, .function:
            Issue.record("Expected fixed maxVideosPerCall == 1")
        }
    }

    @Test("constructor supports different model IDs")
    func constructorDifferentModelId() async throws {
        let model = makeModel(modelId: "luma-ray-2")
        #expect(model.modelId == "luma-ray-2")
    }

    @Test("doGenerate passes correct parameters including prompt")
    func passesPrompt() async throws {
        actor Capture {
            var calls: [URLRequest] = []
            func record(_ request: URLRequest) { calls.append(request) }
            func first() -> URLRequest? { calls.first }
        }

        let capture = Capture()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            await capture.record(request)
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:])
        )

        guard let first = await capture.first(),
              let body = first.httpBody else {
            Issue.record("Missing request capture")
            return
        }

        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json == .object(["prompt": .string(prompt)]))
    }

    @Test("doGenerate passes seed when provided")
    func passesSeed() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }

        let capture = Capture()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: data)
                    await capture.store(json)
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(prompt: prompt, n: 1, seed: 42, providerOptions: [:])
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "seed": .number(42),
        ]))
    }

    @Test("doGenerate passes aspect ratio when provided")
    func passesAspectRatio() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }

        let capture = Capture()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: data)
                    await capture.store(json)
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(prompt: prompt, n: 1, aspectRatio: "16:9", providerOptions: [:])
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "aspect_ratio": .string("16:9"),
        ]))
    }

    @Test("doGenerate converts duration to string format")
    func convertsDuration() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }

        let capture = Capture()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    let json = try JSONDecoder().decode(JSONValue.self, from: data)
                    await capture.store(json)
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(prompt: prompt, n: 1, duration: 5, providerOptions: [:])
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "duration": .string("5s"),
        ]))
    }

    @Test("doGenerate passes headers")
    func passesHeaders() async throws {
        actor Capture {
            var headers: [String: String] = [:]
            func store(_ headers: [String: String]) { self.headers = headers }
            func snapshot() -> [String: String] { headers }
        }

        let capture = Capture()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                let lowered = Dictionary(
                    uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
                )
                await capture.store(lowered)
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(
            headers: { ["Custom-Provider-Header": "provider-header-value"] },
            fetch: fetch
        )

        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [:],
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        let headers = await capture.snapshot()
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("doGenerate returns video with correct data")
    func returnsVideo() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "width": 1920,
                "height": 1080,
                "duration": 5.0,
                "fps": 24,
                "content_type": "video/mp4",
            ],
            "seed": 12345,
            "timings": [
                "inference": 45.5,
            ],
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))

        #expect(result.videos == [.url(url: "https://fal.media/files/video-output.mp4", mediaType: "video/mp4")])
        #expect(result.warnings == [])
        #expect(result.providerMetadata == [
            "fal": [
                "videos": .array([
                    .object([
                        "url": .string("https://fal.media/files/video-output.mp4"),
                        "width": .number(1920),
                        "height": .number(1080),
                        "duration": .number(5.0),
                        "fps": .number(24),
                        "contentType": .string("video/mp4"),
                    ])
                ]),
                "seed": .number(12345),
                "timings": .object([
                    "inference": .number(45.5),
                ]),
            ]
        ])

        #expect(result.response.modelId == "luma-dream-machine")
        #expect(result.response.timestamp.timeIntervalSince1970 == 1_704_067_200)
        #expect(result.response.headers?["content-type"] == "application/json")
    }

    @Test("providerMetadata includes has_nsfw_concepts when present")
    func providerMetadataIncludesNSFW() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ],
            "has_nsfw_concepts": [false],
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
        #expect(result.providerMetadata?["fal"]?["has_nsfw_concepts"] == .array([.bool(false)]))
    }

    @Test("providerMetadata includes prompt when present in response")
    func providerMetadataIncludesPrompt() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ],
            "prompt": "Enhanced prompt from the model",
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
        #expect(result.providerMetadata?["fal"]?["prompt"] == .string("Enhanced prompt from the model"))
    }

    @Test("image-to-video sends image_url with file data")
    func imageToVideoFile() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let imageData = Data([137, 80, 78, 71]) // PNG magic bytes

        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                image: .file(mediaType: "image/png", data: .binary(imageData), providerOptions: nil),
                providerOptions: [:]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "image_url": .string("data:image/png;base64,iVBORw=="),
        ]))
    }

    @Test("image-to-video sends image_url with URL-based image")
    func imageToVideoURL() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                image: .url(url: "https://example.com/input-image.png", providerOptions: nil),
                providerOptions: [:]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "image_url": .string("https://example.com/input-image.png"),
        ]))
    }

    @Test("provider options: maps loop")
    func providerOptionsLoop() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["loop": .bool(true)]]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "loop": .bool(true),
        ]))
    }

    @Test("provider options: maps motionStrength to motion_strength")
    func providerOptionsMotionStrength() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["motionStrength": .number(0.8)]]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "motion_strength": .number(0.8),
        ]))
    }

    @Test("provider options: maps resolution")
    func providerOptionsResolution() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-ray-2"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-ray-2/requests/ray2-request-id"

        let queueResponse = try jsonData([
            "request_id": "ray2-request-id",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/ray2-video.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(modelId: "luma-ray-2", fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["resolution": .string("1080p")]]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "resolution": .string("1080p"),
        ]))
    }

    @Test("provider options: maps negativePrompt to negative_prompt")
    func providerOptionsNegativePrompt() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["negativePrompt": .string("blurry, low quality")]]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "negative_prompt": .string("blurry, low quality"),
        ]))
    }

    @Test("provider options: maps promptOptimizer to prompt_optimizer")
    func providerOptionsPromptOptimizer() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["promptOptimizer": .bool(true)]]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "prompt_optimizer": .bool(true),
        ]))
    }

    @Test("provider options: passes through additional options")
    func providerOptionsPassthrough() async throws {
        actor Capture {
            var body: JSONValue?
            func store(_ body: JSONValue) { self.body = body }
            func snapshot() -> JSONValue? { body }
        }
        let capture = Capture()

        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                if let data = request.httpBody {
                    await capture.store(try JSONDecoder().decode(JSONValue.self, from: data))
                }
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: [
                    "fal": [
                        "custom_param": .string("custom_value"),
                        "another_param": .number(123),
                    ]
                ]
            )
        )

        #expect(await capture.snapshot() == .object([
            "prompt": .string(prompt),
            "custom_param": .string("custom_value"),
            "another_param": .number(123),
        ]))
    }

    @Test("error handling: throws when no response URL is returned")
    func throwsWhenNoResponseURL() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(try jsonData([:])),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message == "No response URL returned from queue endpoint")
        }
    }

    @Test("error handling: throws when no video URL in response")
    func throwsWhenNoVideoURL() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let emptyStatus = try jsonData([:])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(emptyStatus),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch let error as any AISDKError {
            #expect(error.message == "No video URL in response")
        }
    }

    @Test("error handling: surfaces invalid JSON response for malformed status payload")
    func surfacesInvalidJSONResponseForMalformedStatusPayload() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])

        // `video.url` is required when `video` is present.
        let invalidStatus = try jsonData([
            "video": [:]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(invalidStatus),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch let error as APICallError {
            #expect(error.message == "Invalid JSON response")
        }
    }

    @Test("error handling: surfaces API errors from queue endpoint")
    func surfacesQueueAPIErrors() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"

        let errorBody = try jsonData([
            "error": [
                "message": "Invalid prompt",
                "code": 123,
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(errorBody),
                    urlResponse: httpResponse(url: request.url!, statusCode: 400, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))
            Issue.record("Expected error")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
        }
    }

    @Test("polling: polls until video is ready")
    func pollsUntilReady() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int {
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

        let pollCount = Counter()
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/poll-test-id"

        let queueResponse = try jsonData([
            "request_id": "poll-test-id",
            "response_url": statusUrl,
        ])

        let inProgress = try jsonData(["detail": "Request is still in progress"])
        let finalStatus = try jsonData([
            "video": [
                "url": "https://fal.media/files/final-video.mp4",
                "content_type": "video/mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl && request.httpMethod == "POST" {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }

            if urlString == statusUrl && request.httpMethod == "GET" {
                let count = pollCount.next()
                if count < 3 {
                    return FetchResponse(
                        body: .data(inProgress),
                        urlResponse: httpResponse(url: request.url!, statusCode: 500, headers: ["Content-Type": "application/json"])
                    )
                }
                return FetchResponse(
                    body: .data(finalStatus),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }

            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(
            options: VideoModelV3CallOptions(
                prompt: prompt,
                n: 1,
                providerOptions: ["fal": ["pollIntervalMs": .number(10)]]
            )
        )

        #expect(pollCount.current() == 3)
        #expect(result.videos.first == .url(url: "https://fal.media/files/final-video.mp4", mediaType: "video/mp4"))
    }

    @Test("polling: times out after pollTimeoutMs")
    func pollingTimeout() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/timeout-test-id"

        let queueResponse = try jsonData([
            "request_id": "timeout-test-id",
            "response_url": statusUrl,
        ])
        let inProgress = try jsonData(["detail": "Request is still in progress"])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl && request.httpMethod == "POST" {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl && request.httpMethod == "GET" {
                return FetchResponse(
                    body: .data(inProgress),
                    urlResponse: httpResponse(url: request.url!, statusCode: 500, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(
                options: VideoModelV3CallOptions(
                    prompt: prompt,
                    n: 1,
                    providerOptions: [
                        "fal": [
                            "pollIntervalMs": .number(10),
                            "pollTimeoutMs": .number(50),
                        ]
                    ]
                )
            )
            Issue.record("Expected timeout error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("timed out"))
        }
    }

    @Test("polling: respects abort signal")
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
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/abort-test-id"

        let queueResponse = try jsonData([
            "request_id": "abort-test-id",
            "response_url": statusUrl,
        ])
        let inProgress = try jsonData(["detail": "Request is still in progress"])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl && request.httpMethod == "POST" {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl && request.httpMethod == "GET" {
                Task {
                    // Flip the abort signal while the polling loop is sleeping (mirrors upstream test timing).
                    try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
                    flag.abort()
                }
                return FetchResponse(
                    body: .data(inProgress),
                    urlResponse: httpResponse(url: request.url!, statusCode: 500, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)

        do {
            _ = try await model.doGenerate(
                options: VideoModelV3CallOptions(
                    prompt: prompt,
                    n: 1,
                    providerOptions: ["fal": ["pollIntervalMs": .number(100)]],
                    abortSignal: { flag.isAborted() }
                )
            )
            Issue.record("Expected abort error")
        } catch let error as any AISDKError {
            #expect(error.message.contains("aborted"))
        }
    }

    @Test("defaults mediaType to video/mp4 when content_type is missing")
    func defaultMediaType() async throws {
        let queueUrl = "https://queue.fal.run/fal-ai/luma-dream-machine"
        let statusUrl = "https://queue.fal.run/fal-ai/luma-dream-machine/requests/test-request-id-123"

        let queueResponse = try jsonData([
            "request_id": "test-request-id-123",
            "response_url": statusUrl,
        ])
        let statusResponse = try jsonData([
            "video": [
                "url": "https://fal.media/files/video-output.mp4",
            ]
        ])

        let fetch: FetchFunction = { request in
            let urlString = request.url!.absoluteString
            if urlString == queueUrl {
                return FetchResponse(
                    body: .data(queueResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            if urlString == statusUrl {
                return FetchResponse(
                    body: .data(statusResponse),
                    urlResponse: httpResponse(url: request.url!, statusCode: 200, headers: ["Content-Type": "application/json"])
                )
            }
            Issue.record("Unexpected URL: \(urlString)")
            throw CancellationError()
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: VideoModelV3CallOptions(prompt: prompt, n: 1, providerOptions: [:]))

        #expect(result.videos.first == .url(url: "https://fal.media/files/video-output.mp4", mediaType: "video/mp4"))
    }
}
