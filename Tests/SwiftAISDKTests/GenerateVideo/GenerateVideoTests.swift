/**
 Tests for video generation entry point.

 Port of `@ai-sdk/ai/src/generate-video/generate-video.test.ts`.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("GenerateVideo Tests", .serialized)
struct GenerateVideoTests {
    private let prompt = "a cat walking on a beach"
    private let testDate: Date = {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }()

    private let mp4Base64 = "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDE="
    private let webmBase64 = "GkXfo59ChoEBQveBAULygQRC84EIQoKEd2Vib"

    private func decodeBase64(_ value: String) -> Data {
        try! convertBase64ToData(value)
    }

    private func createMockResponse(
        videos: [VideoModelV3VideoData],
        warnings: [SharedV3Warning] = [],
        timestamp: Date? = nil,
        modelId: String? = nil,
        providerMetadata: SharedV3ProviderMetadata? = nil,
        headers: [String: String]? = nil
    ) -> VideoModelV3GenerateResult {
        let defaultMetadata: SharedV3ProviderMetadata = [
            "testProvider": [
                "videos": .array(Array(repeating: .null, count: videos.count))
            ]
        ]

        return VideoModelV3GenerateResult(
            videos: videos,
            warnings: warnings,
            providerMetadata: providerMetadata ?? defaultMetadata,
            response: VideoModelV3ResponseInfo(
                timestamp: timestamp ?? Date(),
                modelId: modelId ?? "test-model-id",
                headers: headers ?? [:]
            )
        )
    }

    private func resetWarningHooks() {
        logWarningsObserver = nil
        AI_SDK_LOG_WARNINGS = nil
        resetLogWarningsState()
    }

    @Test("should send args to doGenerate")
    func sendsArgsToDoGenerate() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()
        let abortSignal: @Sendable () -> Bool = { false }

        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "loop": .bool(true)
            ]
        ]

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: prompt,
            aspectRatio: "16:9",
            resolution: "1920x1080",
            duration: 5,
            fps: 30,
            seed: 12345,
            providerOptions: providerOptions,
            abortSignal: abortSignal,
            headers: [
                "custom-request-header": "request-header-value"
            ]
        )

        let options = await optionsBox.wait()

        #expect(options.n == 1)
        #expect(options.prompt == prompt)
        #expect(options.image == nil)
        #expect(options.aspectRatio == "16:9")
        #expect(options.resolution == "1920x1080")
        #expect(options.duration == 5)
        #expect(options.fps == 30)
        #expect(options.seed == 12345)
        #expect(options.abortSignal?() == false)

        let expectedProviderOptions = providerOptions["mock-provider"]?["loop"]
        let actualProviderOptions = options.providerOptions?["mock-provider"]?["loop"]
        #expect(actualProviderOptions == expectedProviderOptions)

        #expect(options.headers?["custom-request-header"] == "request-header-value")
        let userAgentValue = options.headers?["user-agent"] ?? ""
        #expect(userAgentValue == "ai/" + SwiftAISDK.VERSION)
    }

    @Test("should return warnings")
    func returnsWarnings() async throws {
        let expected: [VideoGenerationWarning] = [
            .other(message: "Setting is not supported")
        ]

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ],
                        warnings: expected
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.warnings == expected)
    }

    @Test("should call logWarnings with the correct warnings")
    func logsWarnings() async throws {
        try await LogWarningsTestLock.shared.withLock {
            let warning1: VideoGenerationWarning = .other(message: "Setting is not supported")
            let warning2: VideoGenerationWarning = .unsupported(feature: "duration", details: "Duration parameter not supported")
            let expected = [warning1, warning2]

            guard let token = LogWarningsTestLock.currentOwnerID() else {
                Issue.record("Missing log warnings scope token")
                return
            }

            let warningsBox = LockedBox<[VideoGenerationWarning]>()
            logWarningsObserver = { warnings in
                guard LogWarningsTestLock.currentOwnerID() == token else { return }
                let videoWarnings = warnings.compactMap { warning -> VideoGenerationWarning? in
                    guard case let .videoModel(videoWarning) = warning else { return nil }
                    return videoWarning
                }
                warningsBox.set(videoWarnings)
            }
            resetLogWarningsState()
            defer { resetWarningHooks() }

            _ = try await experimental_generateVideo(
                model: MockVideoModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            warnings: expected
                        )
                    }
                ),
                prompt: prompt
            )

            guard let observed = warningsBox.get() else {
                Issue.record("Expected logWarnings to be invoked with warnings.")
                return
            }
            #expect(observed == expected)
        }
    }

    @Test("should return generated videos with correct mime types (base64)")
    func returnsVideosWithMediaTypes_base64() async throws {
        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                            .base64(data: self.webmBase64, mediaType: "video/webm"),
                        ]
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.videos.count == 2)
        #expect(result.videos[0].mediaType == "video/mp4")
        #expect(result.videos[1].mediaType == "video/webm")
    }

    @Test("should return the first video")
    func returnsFirstVideo() async throws {
        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                            .base64(data: self.webmBase64, mediaType: "video/webm"),
                        ]
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.video.mediaType == "video/mp4")
    }

    @Test("should return generated videos (binary)")
    func returnsVideos_binary() async throws {
        let binaryData = decodeBase64(mp4Base64)

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .binary(data: binaryData, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.videos.count == 1)
        #expect(result.video.data == binaryData)
    }

    @Test("should fetch and return videos from URLs")
    func returnsVideos_urlDownload() async throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let mp4Bytes = decodeBase64(mp4Base64)

        try await withMockedURL(url: url) { _ in
            (status: 200, headers: ["Content-Type": "video/mp4"], body: mp4Bytes)
        } run: {
            let result = try await experimental_generateVideo(
                model: MockVideoModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            videos: [
                                .url(url: url.absoluteString, mediaType: "video/mp4")
                            ]
                        )
                    }
                ),
                prompt: prompt
            )

            #expect(result.videos.count == 1)
            #expect(result.video.mediaType == "video/mp4")
        }
    }

    @Test("should throw DownloadError when fetch fails")
    func throwsDownloadError() async throws {
        let url = URL(string: "https://example.com/video.mp4")!

        do {
            try await withMockedURL(url: url) { _ in
                (status: 404, headers: ["Content-Type": "text/plain"], body: Data())
            } run: {
                _ = try await experimental_generateVideo(
                    model: MockVideoModelV3(
                        doGenerate: { _ in
                            self.createMockResponse(
                                videos: [
                                    .url(url: url.absoluteString, mediaType: "video/mp4")
                                ]
                            )
                        }
                    ),
                    prompt: prompt
                )
            }

            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.message == "Failed to download \(url.absoluteString): 404 Not Found")
        }
    }

    @Test("should detect mediaType via signature when provider and download return application/octet-stream")
    func detectsMediaTypeFromSignature() async throws {
        let url = URL(string: "https://example.com/video")!
        let mp4Bytes = decodeBase64(mp4Base64)

        try await withMockedURL(url: url) { _ in
            (status: 200, headers: ["Content-Type": "application/octet-stream"], body: mp4Bytes)
        } run: {
            let result = try await experimental_generateVideo(
                model: MockVideoModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            videos: [
                                .url(url: url.absoluteString, mediaType: "application/octet-stream")
                            ]
                        )
                    }
                ),
                prompt: prompt
            )

            #expect(result.video.mediaType == "video/mp4")
        }
    }

    @Test("should generate videos when several calls are required")
    func generatesAcrossMultipleCalls() async throws {
        let counter = Counter()

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                maxVideosPerCall: .value(2),
                doGenerate: { options in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        #expect(options.n == 2)
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                                .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                            ]
                        )
                    case 1:
                        #expect(options.n == 1)
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.webmBase64, mediaType: "video/webm")
                            ]
                        )
                    default:
                        Issue.record("Unexpected call")
                        throw CancellationError()
                    }
                }
            ),
            prompt: prompt,
            n: 3
        )

        #expect(result.videos.count == 3)
    }

    @Test("should aggregate warnings across multiple calls")
    func aggregatesWarningsAcrossCalls() async throws {
        let warning1: VideoGenerationWarning = .other(message: "Warning from call 1")
        let warning2: VideoGenerationWarning = .other(message: "Warning from call 2")
        let counter = Counter()

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                maxVideosPerCall: .value(1),
                doGenerate: { _ in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            warnings: [warning1]
                        )
                    case 1:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            warnings: [warning2]
                        )
                    default:
                        Issue.record("Unexpected call")
                        throw CancellationError()
                    }
                }
            ),
            prompt: prompt,
            n: 2
        )

        #expect(result.warnings == [warning1, warning2])
    }

    @Test("should generate with maxVideosPerCall returned by model")
    func supportsModelMaxVideosPerCallFunction() async throws {
        let counter = Counter()
        let maxVideosCalls = SingleValueBox<String>()

        let model = MockVideoModelV3(
            maxVideosPerCall: .function({ modelId in
                await maxVideosCalls.set(modelId)
                return 2
            }),
            doGenerate: { options in
                let index = await counter.next()
                switch index {
                case 0:
                    #expect(options.n == 2)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                            .base64(data: self.mp4Base64, mediaType: "video/mp4"),
                        ]
                    )
                case 1:
                    #expect(options.n == 1)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.webmBase64, mediaType: "video/webm")
                        ]
                    )
                default:
                    Issue.record("Unexpected call")
                    throw CancellationError()
                }
            }
        )

        let result = try await experimental_generateVideo(
            model: model,
            prompt: prompt,
            n: 3
        )

        #expect(result.videos.count == 3)
        #expect(await maxVideosCalls.wait() == "mock-model-id")
    }

    @Test("should throw NoVideoGeneratedError when no videos are returned")
    func throwsNoVideoGeneratedError() async throws {
        do {
            _ = try await experimental_generateVideo(
                model: MockVideoModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            videos: [],
                            timestamp: self.testDate
                        )
                    }
                ),
                prompt: prompt
            )
            Issue.record("Expected NoVideoGeneratedError")
        } catch let error as NoVideoGeneratedError {
            #expect(error.name == "AI_NoVideoGeneratedError")
            #expect(error.message == "No video generated.")
            #expect(error.responses?.count == 1)
            #expect(error.responses?.first?.timestamp == testDate)
        }
    }

    @Test("should include response headers in error when no videos generated")
    func includesHeadersInNoVideoGeneratedError() async throws {
        do {
            _ = try await experimental_generateVideo(
                model: MockVideoModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            videos: [],
                            timestamp: self.testDate,
                            headers: [
                                "custom-response-header": "response-header-value"
                            ]
                        )
                    }
                ),
                prompt: prompt
            )
            Issue.record("Expected NoVideoGeneratedError")
        } catch let error as NoVideoGeneratedError {
            let headers = error.responses?.first?.headers ?? [:]
            #expect(headers["custom-response-header"] == "response-header-value")
        }
    }

    @Test("should return response metadata")
    func returnsResponseMetadata() async throws {
        let testHeaders = ["x-test": "value"]

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ],
                        timestamp: self.testDate,
                        modelId: "test-model",
                        headers: testHeaders
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.responses == [
            VideoModelResponseMetadata(
                timestamp: testDate,
                modelId: "test-model",
                headers: testHeaders,
                providerMetadata: [
                    "testProvider": [
                        "videos": .array([.null])
                    ]
                ]
            )
        ])
    }

    @Test("should return provider metadata")
    func returnsProviderMetadata() async throws {
        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ],
                        timestamp: self.testDate,
                        modelId: "test-model",
                        providerMetadata: [
                            "testProvider": [
                                "videos": [
                                    ["seed": 12345, "duration": 5]
                                ]
                            ]
                        ],
                        headers: [:]
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.providerMetadata == [
            "testProvider": [
                "videos": [
                    ["seed": 12345, "duration": 5]
                ]
            ]
        ])
    }

    @Test("should merge provider metadata from multiple calls")
    func mergesProviderMetadata() async throws {
        let counter = Counter()

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                maxVideosPerCall: .value(1),
                doGenerate: { _ in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "testProvider": [
                                    "videos": [
                                        ["seed": 111]
                                    ]
                                ]
                            ]
                        )
                    case 1:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "testProvider": [
                                    "videos": [
                                        ["seed": 222]
                                    ]
                                ]
                            ]
                        )
                    default:
                        Issue.record("Unexpected call")
                        throw CancellationError()
                    }
                }
            ),
            prompt: prompt,
            n: 2
        )

        #expect(result.providerMetadata == [
            "testProvider": [
                "videos": [
                    ["seed": 111],
                    ["seed": 222],
                ]
            ]
        ])
    }

    @Test("should handle gateway provider metadata")
    func mergesGatewayProviderMetadata() async throws {
        let counter = Counter()

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                maxVideosPerCall: .value(1),
                doGenerate: { _ in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "gateway": [
                                    "videos": [
                                        ["seed": 111]
                                    ],
                                    "routing": ["provider": "fal"],
                                ]
                            ]
                        )
                    case 1:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "gateway": [
                                    "videos": [
                                        ["seed": 222]
                                    ],
                                    "cost": "0.08",
                                ]
                            ]
                        )
                    default:
                        Issue.record("Unexpected call")
                        throw CancellationError()
                    }
                }
            ),
            prompt: prompt,
            n: 2
        )

        #expect(result.providerMetadata["gateway"] == [
            "videos": [
                ["seed": 111],
                ["seed": 222],
            ],
            "routing": ["provider": "fal"],
            "cost": "0.08",
        ])
    }

    @Test("should handle nil providerMetadata")
    func handlesNilProviderMetadata() async throws {
        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { _ in
                    VideoModelV3GenerateResult(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ],
                        warnings: [],
                        providerMetadata: nil,
                        response: VideoModelV3ResponseInfo(
                            timestamp: Date(),
                            modelId: "test-model-id",
                            headers: [:]
                        )
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.providerMetadata.isEmpty)
    }

    @Test("should preserve per-call providerMetadata in responses array")
    func preservesPerCallProviderMetadata() async throws {
        let counter = Counter()

        let result = try await experimental_generateVideo(
            model: MockVideoModelV3(
                maxVideosPerCall: .value(1),
                doGenerate: { _ in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "testProvider": [
                                    "videos": [
                                        ["seed": 111, "duration": 5]
                                    ],
                                    "requestId": "req-001",
                                ]
                            ]
                        )
                    case 1:
                        return self.createMockResponse(
                            videos: [
                                .base64(data: self.mp4Base64, mediaType: "video/mp4")
                            ],
                            providerMetadata: [
                                "testProvider": [
                                    "videos": [
                                        ["seed": 222, "duration": 8]
                                    ],
                                    "requestId": "req-002",
                                ]
                            ]
                        )
                    default:
                        Issue.record("Unexpected call")
                        throw CancellationError()
                    }
                }
            ),
            prompt: prompt,
            n: 2
        )

        #expect(result.responses.count == 2)
        #expect(result.responses[0].providerMetadata == [
            "testProvider": [
                "videos": [
                    ["seed": 111, "duration": 5]
                ],
                "requestId": "req-001",
            ]
        ])
        #expect(result.responses[1].providerMetadata == [
            "testProvider": [
                "videos": [
                    ["seed": 222, "duration": 8]
                ],
                "requestId": "req-002",
            ]
        ])

        #expect(result.providerMetadata == [
            "testProvider": [
                "videos": [
                    ["seed": 111, "duration": 5],
                    ["seed": 222, "duration": 8],
                ],
                "requestId": "req-002",
            ]
        ])
    }

    @Test("should handle string prompt")
    func promptNormalization_stringPrompt() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: "a simple text prompt"
        )

        let options = await optionsBox.wait()
        #expect(options.prompt == "a simple text prompt")
        #expect(options.image == nil)
    }

    @Test("should handle object prompt with text and image")
    func promptNormalization_textAndImage() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: .imageToVideo(image: .string(pngBase64), text: "image to video prompt")
        )

        let options = await optionsBox.wait()
        #expect(options.prompt == "image to video prompt")
        #expect(options.image != nil)
    }

    @Test("should handle URL image in prompt")
    func promptNormalization_urlImage() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: .imageToVideo(image: .string("https://example.com/image.png"), text: nil)
        )

        let options = await optionsBox.wait()
        #expect(options.image == .url(url: "https://example.com/image.png", providerOptions: nil))
    }

    @Test("should handle data URL image in prompt")
    func promptNormalization_dataUrlImage() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
        let dataUrl = "data:image/png;base64,\(pngBase64)"

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: .imageToVideo(image: .string(dataUrl), text: nil)
        )

        let options = await optionsBox.wait()
        let expectedData = decodeBase64(pngBase64)
        #expect(options.image == .file(mediaType: "image/png", data: .binary(expectedData), providerOptions: nil))
    }

    @Test("should detect image mediaType from raw base64 string via signature detection")
    func promptNormalization_detectMediaTypeFromRawBase64() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: .imageToVideo(image: .string(pngBase64), text: nil)
        )

        let options = await optionsBox.wait()
        let expectedData = decodeBase64(pngBase64)
        #expect(options.image == .file(mediaType: "image/png", data: .binary(expectedData), providerOptions: nil))
    }

    @Test("should detect image mediaType from Data via signature detection")
    func promptNormalization_detectMediaTypeFromBytes() async throws {
        let optionsBox = SingleValueBox<VideoModelV3CallOptions>()
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

        _ = try await experimental_generateVideo(
            model: MockVideoModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        videos: [
                            .base64(data: self.mp4Base64, mediaType: "video/mp4")
                        ]
                    )
                }
            ),
            prompt: .imageToVideo(image: .data(jpegBytes), text: nil)
        )

        let options = await optionsBox.wait()
        #expect(options.image == .file(mediaType: "image/jpeg", data: .binary(jpegBytes), providerOptions: nil))
    }
}

// MARK: - Test support

private actor SingleValueBox<Value: Sendable> {
    private var value: Value?
    private var continuation: CheckedContinuation<Value, Never>?

    func set(_ value: Value) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    func wait() async -> Value {
        if let value {
            return value
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@preconcurrency private final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) async throws -> (status: Int, headers: [String: String], body: Data)

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [URL: Handler] = [:]

        func set(_ handler: @escaping Handler, for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            handlers[url] = handler
        }

        func remove(for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            handlers.removeValue(forKey: url)
        }

        func get(for url: URL) -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[url]
        }
    }

    private static let registry = Registry()

    static func install(handler: @escaping Handler, for url: URL) {
        registry.set(handler, for: url)
    }

    static func removeHandler(for url: URL) {
        registry.remove(for: url)
    }

    static func handler(for url: URL) -> Handler? {
        registry.get(for: url)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return handler(for: url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            guard let url = request.url, let handler = Self.handler(for: url) else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            do {
                let result = try await handler(request)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: result.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: result.headers
                )!

                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private func withMockedURL<T>(
    url: URL,
    handler: @escaping MockURLProtocol.Handler,
    run: () async throws -> T
) async throws -> T {
    MockURLProtocol.install(handler: handler, for: url)
    guard URLProtocol.registerClass(MockURLProtocol.self) else {
        MockURLProtocol.removeHandler(for: url)
        throw CancellationError()
    }

    defer {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.removeHandler(for: url)
    }

    return try await run()
}
