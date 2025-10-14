/**
 Tests for image generation entry point.

 Port of `@ai-sdk/ai/src/generate-image/generate-image.test.ts`.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("GenerateImage Tests", .serialized)
struct GenerateImageTests {
    private let prompt = "sunny day at the beach"
    private let testDate: Date = {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }()

    private let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==" // 1x1 transparent PNG
    private let jpegBase64 =
        "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=" // 1x1 black JPEG
    private let gifBase64 =
        "R0lGODlhAQABAIAAAAUEBAAAACwAAAAAAQABAAACAkQBADs=" // 1x1 transparent GIF

    // MARK: - Helpers

    private enum TestImages {
        case base64([String])
        case data([Data])
    }

    private func decodeBase64(_ value: String) -> Data {
        try! convertBase64ToData(value)
    }

    private func createMockResponse(
        images: TestImages,
        warnings: [ImageModelV3CallWarning] = [],
        timestamp: Date? = nil,
        modelId: String? = nil,
        providerMetadata: ImageModelV3ProviderMetadata? = nil,
        headers: [String: String]? = nil
    ) -> ImageModelV3GenerateResult {
        let generatedImages: ImageModelV3GeneratedImages
        let imageCount: Int

        switch images {
        case .base64(let values):
            generatedImages = .base64(values)
            imageCount = values.count
        case .data(let values):
            generatedImages = .binary(values)
            imageCount = values.count
        }

        let metadata = providerMetadata ?? [
            "testProvider": ImageModelV3ProviderMetadataValue(
                images: Array(repeating: .null, count: imageCount),
                additionalData: nil
            )
        ]

        return ImageModelV3GenerateResult(
            images: generatedImages,
            warnings: warnings,
            providerMetadata: metadata,
            response: ImageModelV3ResponseInfo(
                timestamp: timestamp ?? Date(),
                modelId: modelId ?? "test-model-id",
                headers: headers
            )
        )
    }

    private func resetWarningHooks() {
        logWarningsObserver = nil
        AI_SDK_LOG_WARNINGS = nil
        resetLogWarningsState()
    }

    // MARK: - Tests

    @Test("should send args to doGenerate")
    func sendsArgsToDoGenerate() async throws {
        let optionsBox = SingleValueBox<ImageModelV3CallOptions>()
        let abortSignal: @Sendable () -> Bool = { false }
        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "style": .string("vivid")
            ]
        ]

        _ = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { options in
                    await optionsBox.set(options)
                    return self.createMockResponse(
                        images: .base64([self.pngBase64])
                    )
                }
            ),
            prompt: prompt,
            size: "1024x1024",
            aspectRatio: "16:9",
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
        #expect(options.size == "1024x1024")
        #expect(options.aspectRatio == "16:9")
        #expect(options.seed == 12345)
        #expect(options.abortSignal?() == false)

        let expectedProviderOptions = providerOptions["mock-provider"]?["style"]
        let actualProviderOptions = options.providerOptions?["mock-provider"]?["style"]
        #expect(actualProviderOptions == expectedProviderOptions)

        #expect(options.headers?["custom-request-header"] == "request-header-value")
        let headers = options.headers ?? [:]
        let userAgentValue = headers["user-agent"] ?? ""
        let expectedUserAgent: String = "ai/" + SwiftAISDK.VERSION
        #expect(userAgentValue == expectedUserAgent)
    }

    @Test("should return warnings")
    func returnsWarnings() async throws {
        let expected: [ImageGenerationWarning] = [
            .other(message: "Setting is not supported")
        ]

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64]),
                        warnings: expected
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.warnings == expected)
    }

    @Test("should call logWarnings with the correct warnings", .disabled("logWarningsObserver conflict - Task created for investigation"))
    func logsWarnings() async throws {
        let warning1: ImageGenerationWarning = .other(message: "Setting is not supported")
        let warning2: ImageGenerationWarning = .unsupportedSetting(setting: "size", details: "Size parameter not supported")
        let expected = [warning1, warning2]

        let warningsBox = LockedBox<[ImageGenerationWarning]>()
        logWarningsObserver = { warnings in
            let imageWarnings = warnings.compactMap { warning -> ImageGenerationWarning? in
                guard case let .imageModel(imageWarning) = warning else {
                    return nil
                }
                return imageWarning
            }
            warningsBox.set(imageWarnings)
        }
        resetLogWarningsState()

        defer { resetWarningHooks() }

        _ = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64]),
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

    @Test("should call logWarnings with aggregated warnings from multiple calls")
    func logsAggregatedWarnings() async throws {
        let warning1: ImageGenerationWarning = .other(message: "Warning from call 1")
        let warning2: ImageGenerationWarning = .other(message: "Warning from call 2")

        let warningsBox = LockedBox<[ImageGenerationWarning]>()
        logWarningsObserver = { warnings in
            let imageWarnings = warnings.compactMap { warning -> ImageGenerationWarning? in
                guard case let .imageModel(imageWarning) = warning else {
                    return nil
                }
                return imageWarning
            }
            warningsBox.set(imageWarnings)
        }
        resetLogWarningsState()
        defer { resetWarningHooks() }

        let counter = Counter()

        _ = try await generateImage(
            model: MockImageModelV3(
                maxImagesPerCall: .value(1),
                doGenerate: { _ in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        return self.createMockResponse(
                            images: .base64([self.pngBase64]),
                            warnings: [warning1]
                        )
                    case 1:
                        return self.createMockResponse(
                            images: .base64([self.jpegBase64]),
                            warnings: [warning2]
                        )
                    default:
                        return self.createMockResponse(images: .base64([]))
                    }
                }
            ),
            prompt: prompt,
            n: 2
        )

        guard let observed = warningsBox.get() else {
            Issue.record("Expected logWarnings to be invoked with warnings.")
            return
        }
        #expect(observed == [warning1, warning2])
    }

    @Test("should call logWarnings with empty array when no warnings are present")
    func logsEmptyWarnings() async throws {
        let warningsBox = LockedBox<[ImageGenerationWarning]>()
        logWarningsObserver = { warnings in
            let imageWarnings = warnings.compactMap { warning -> ImageGenerationWarning? in
                guard case let .imageModel(imageWarning) = warning else {
                    return nil
                }
                return imageWarning
            }
            warningsBox.set(imageWarnings)
        }
        resetLogWarningsState()
        defer { resetWarningHooks() }

        _ = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64]),
                        warnings: []
                    )
                }
            ),
            prompt: prompt
        )

        guard let observed = warningsBox.get() else {
            Issue.record("Expected logWarnings to be invoked with warnings.")
            return
        }
        #expect(observed.isEmpty)
    }

    @Test("should return generated images with correct mime types")
    func returnsImagesWithMimeTypes() async throws {
        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64, self.jpegBase64])
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.images.count == 2)

        if result.images.count == 2 {
            let first = result.images[0]
            let second = result.images[1]

            #expect(first.base64 == pngBase64)
            #expect(first.data == decodeBase64(pngBase64))
            #expect(first.mediaType == "image/png")

            #expect(second.base64 == jpegBase64)
            #expect(second.data == decodeBase64(jpegBase64))
            #expect(second.mediaType == "image/jpeg")
        }
    }

    @Test("should return the first image with correct mime type")
    func returnsFirstImage() async throws {
        let result = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64, self.jpegBase64])
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.image.base64 == pngBase64)
        #expect(result.image.data == decodeBase64(pngBase64))
        #expect(result.image.mediaType == "image/png")
    }

    @Test("should return generated images for binary data")
    func returnsBinaryImages() async throws {
        let binaryImages = [decodeBase64(pngBase64), decodeBase64(jpegBase64)]

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .data(binaryImages)
                    )
                }
            ),
            prompt: prompt
        )

        let base64Images = result.images.map { $0.base64 }
        #expect(base64Images == binaryImages.map(convertDataToBase64))

        let dataImages = result.images.map { $0.data }
        #expect(dataImages == binaryImages)
    }

    @Test("should generate images across multiple calls")
    func generatesImagesAcrossCalls() async throws {
        let base64Images = [pngBase64, jpegBase64, gifBase64]
        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "style": .string("vivid")
            ]
        ]
        let requestHeaders: [String: String] = [
            "custom-request-header": "request-header-value"
        ]
        let counter = Counter()

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                maxImagesPerCall: .value(2),
                doGenerate: { options in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        #expect(options.n == 2)
                        #expect(options.prompt == self.prompt)
                        #expect(options.seed == 12345)
                        #expect(options.size == "1024x1024")
                        #expect(options.aspectRatio == "16:9")
                        #expect(options.providerOptions?["mock-provider"]?["style"] == .string("vivid"))
                        #expect(options.headers?["custom-request-header"] == "request-header-value")
                        #expect(options.headers?["user-agent"] == "ai/" + SwiftAISDK.VERSION)
                        return self.createMockResponse(
                            images: .base64(Array(base64Images.prefix(2)))
                        )
                    case 1:
                        #expect(options.n == 1)
                        #expect(options.prompt == self.prompt)
                        #expect(options.seed == 12345)
                        #expect(options.size == "1024x1024")
                        #expect(options.aspectRatio == "16:9")
                        #expect(options.providerOptions?["mock-provider"]?["style"] == .string("vivid"))
                        #expect(options.headers?["custom-request-header"] == "request-header-value")
                        #expect(options.headers?["user-agent"] == "ai/" + SwiftAISDK.VERSION)
                        return self.createMockResponse(
                            images: .base64([base64Images[2]])
                        )
                    default:
                        return self.createMockResponse(images: .base64([]))
                    }
                }
            ),
            prompt: prompt,
            n: 3,
            size: "1024x1024",
            aspectRatio: "16:9",
            seed: 12345,
            providerOptions: providerOptions,
            headers: requestHeaders
        )

        #expect(result.images.map { $0.base64 } == base64Images)
    }

    @Test("should aggregate warnings across multiple calls")
    func aggregatesWarningsAcrossCalls() async throws {
        let base64Images = [pngBase64, jpegBase64, gifBase64]
        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "style": .string("vivid")
            ]
        ]
        let requestHeaders: [String: String] = [
            "custom-request-header": "request-header-value"
        ]
        let counter = Counter()

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                maxImagesPerCall: .value(2),
                doGenerate: { options in
                    let index = await counter.next()
                    switch index {
                    case 0:
                        #expect(options.n == 2)
                        return self.createMockResponse(
                            images: .base64(Array(base64Images.prefix(2))),
                            warnings: [.other(message: "1")]
                        )
                    case 1:
                        #expect(options.n == 1)
                        return self.createMockResponse(
                            images: .base64([base64Images[2]]),
                            warnings: [.other(message: "2")]
                        )
                    default:
                        return self.createMockResponse(images: .base64([]))
                    }
                }
            ),
            prompt: prompt,
            n: 3,
            size: "1024x1024",
            aspectRatio: "16:9",
            seed: 12345,
            providerOptions: providerOptions,
            headers: requestHeaders
        )

        #expect(result.warnings == [
            .other(message: "1"),
            .other(message: "2")
        ])
    }

    @Test("should generate with maxImagesPerCall function (sync)")
    func generatesWithMaxImagesPerCallSync() async throws {
        let base64Images = [pngBase64, jpegBase64, gifBase64]
        let spy = MaxImagesPerCallSpy { 2 }
        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "style": .string("vivid")
            ]
        ]
        let requestHeaders: [String: String] = [
            "custom-request-header": "request-header-value"
        ]

        let handler: @Sendable (String) async throws -> Int? = { modelId in
            try await spy.handle(modelId: modelId)
        }

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                maxImagesPerCall: .function(handler),
                doGenerate: { options in
                    switch options.n {
                    case 2:
                        return self.createMockResponse(
                            images: .base64(Array(base64Images.prefix(2)))
                        )
                    case 1:
                        return self.createMockResponse(
                            images: .base64([base64Images[2]])
                        )
                    default:
                        return self.createMockResponse(images: .base64([]))
                    }
                }
            ),
            prompt: prompt,
            n: 3,
            size: "1024x1024",
            aspectRatio: "16:9",
            seed: 12345,
            providerOptions: providerOptions,
            headers: requestHeaders
        )

        let snapshot = await spy.snapshot()
        #expect(snapshot.callCount == 1)
        #expect(snapshot.modelIds == ["mock-model-id"])
        #expect(result.images.map { $0.base64 } == base64Images)
    }

    @Test("should generate with maxImagesPerCall function (async)")
    func generatesWithMaxImagesPerCallAsync() async throws {
        let base64Images = [pngBase64, jpegBase64, gifBase64]
        let spy = MaxImagesPerCallSpy {
            try await Task.sleep(nanoseconds: 1_000)
            return 2
        }
        let providerOptions: ProviderOptions = [
            "mock-provider": [
                "style": .string("vivid")
            ]
        ]
        let requestHeaders: [String: String] = [
            "custom-request-header": "request-header-value"
        ]

        let handler: @Sendable (String) async throws -> Int? = { modelId in
            try await spy.handle(modelId: modelId)
        }

        let result: DefaultGenerateImageResult = try await generateImage(
            model: MockImageModelV3(
                maxImagesPerCall: .function(handler),
                doGenerate: { options in
                    switch options.n {
                    case 2:
                        return self.createMockResponse(
                            images: .base64(Array(base64Images.prefix(2)))
                        )
                    case 1:
                        return self.createMockResponse(
                            images: .base64([base64Images[2]])
                        )
                    default:
                        return self.createMockResponse(images: .base64([]))
                    }
                }
            ),
            prompt: prompt,
            n: 3,
            size: "1024x1024",
            aspectRatio: "16:9",
            seed: 12345,
            providerOptions: providerOptions,
            headers: requestHeaders
        )

        let snapshot = await spy.snapshot()
        #expect(snapshot.callCount == 1)
        #expect(snapshot.modelIds == ["mock-model-id"])
        #expect(result.images.map { $0.base64 } == base64Images)
    }

    @Test("should throw NoImageGeneratedError when no images are returned")
    func throwsWhenNoImages() async throws {
        do {
            _ = try await generateImage(
                model: MockImageModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            images: .base64([]),
                            timestamp: self.testDate
                        )
                    }
                ),
                prompt: prompt
            )
            Issue.record("Expected generateImage to throw.")
        } catch let error as NoImageGeneratedError {
            #expect(error.message == "No image generated.")
            let responses = error.responses
            #expect(responses?.count == 1)
            #expect(responses?.first?.timestamp == testDate)
            #expect(responses?.first?.modelId == "test-model-id")
        }
    }

    @Test("should include response headers in error when no images generated")
    func errorIncludesResponseHeaders() async throws {
        let responseHeaders: [String: String] = Dictionary(uniqueKeysWithValues: [
            ("custom-response-header", "response-header-value"),
            ("user-agent", "ai/" + SwiftAISDK.VERSION)
        ])

        do {
            _ = try await generateImage(
                model: MockImageModelV3(
                    doGenerate: { _ in
                        self.createMockResponse(
                            images: .base64([]),
                            timestamp: self.testDate,
                            headers: responseHeaders
                        )
                    }
                ),
                prompt: prompt
            )
            Issue.record("Expected generateImage to throw.")
        } catch let error as NoImageGeneratedError {
            let responses = error.responses
            #expect(responses?.count == 1)
            #expect(responses?.first?.timestamp == testDate)
            #expect(responses?.first?.modelId == "test-model-id")
            #expect(responses?.first?.headers == responseHeaders)
        }
    }

    @Test("should return response metadata")
    func returnsResponseMetadata() async throws {
        let headers = ["x-test": "value"]

        let result = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64]),
                        timestamp: self.testDate,
                        modelId: "test-model",
                        headers: headers
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.responses == [
            ImageModelResponseMetadata(
                timestamp: testDate,
                modelId: "test-model",
                headers: headers
            )
        ])
    }

    @Test("should return provider metadata")
    func returnsProviderMetadata() async throws {
        let metadata = [
            "testProvider": ImageModelV3ProviderMetadataValue(
                images: [
                    .object(["revisedPrompt": .string("test-revised-prompt")]),
                    .null
                ],
                additionalData: nil
            )
        ]

        let result = try await generateImage(
            model: MockImageModelV3(
                doGenerate: { _ in
                    self.createMockResponse(
                        images: .base64([self.pngBase64, self.pngBase64]),
                        timestamp: self.testDate,
                        modelId: "test-model",
                        providerMetadata: metadata,
                        headers: [:]
                    )
                }
            ),
            prompt: prompt
        )

        #expect(result.providerMetadata.count == 1)
        let providerValue = result.providerMetadata["testProvider"]
        let expectedValue = metadata["testProvider"]
        #expect(providerValue?.images == expectedValue?.images)
        #expect(providerValue?.additionalData == expectedValue?.additionalData)
    }
}

private actor SingleValueBox<Value: Sendable> {
    private var storage: Value?
    private var continuations: [CheckedContinuation<Value, Never>] = []

    init() {}

    func set(_ value: Value) {
        storage = value
        for continuation in continuations {
            continuation.resume(returning: value)
        }
        continuations.removeAll()
    }

    func get() -> Value? {
        storage
    }

    func wait() async -> Value {
        if let value = storage {
            return value
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private actor Counter {
    private var value = 0

    func next() -> Int {
        let current = value
        value += 1
        return current
    }
}

private actor MaxImagesPerCallSpy {
    private var storedCallCount = 0
    private var storedModelIds: [String] = []
    private let provider: @Sendable () async throws -> Int?

    init(provider: @escaping @Sendable () async throws -> Int?) {
        self.provider = provider
    }

    func handle(modelId: String) async throws -> Int? {
        storedCallCount += 1
        storedModelIds.append(modelId)
        return try await provider()
    }

    func snapshot() async -> (callCount: Int, modelIds: [String]) {
        (storedCallCount, storedModelIds)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private var storage: Value?
    private let lock = NSLock()

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
