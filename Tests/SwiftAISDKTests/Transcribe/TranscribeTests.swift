/**
 Tests for transcribe API.

 Port of `@ai-sdk/ai/src/transcribe/transcribe.test.ts`.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let audioData = Data([1, 2, 3, 4])

private let sampleSegments: [TranscriptionModelV4Result.Segment] = [
    .init(text: "This is a", startSecond: 0, endSecond: 2.5),
    .init(text: "sample transcript.", startSecond: 2.5, endSecond: 4.0)
]

private let sampleTranscriptText = "This is a sample transcript."
private let sampleLanguage = "en"
private let sampleDuration: Double = 4.0

private let testDate: Date = {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2024
    components.month = 1
    components.day = 1
    return components.date!
}()

/// Simple box for capturing values inside @Sendable closures.
private final class ValueBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

private func makeMockResponse(
    text: String = sampleTranscriptText,
    segments: [TranscriptionModelV4Result.Segment] = sampleSegments,
    language: String? = sampleLanguage,
    durationInSeconds: Double? = sampleDuration,
    warnings: [TranscriptionWarning] = [],
    timestamp: Date = Date(),
    modelId: String = "test-model-id",
    headers: [String: String]? = nil,
    providerMetadata: [String: [String: JSONValue]]? = nil
) -> TranscriptionModelV3Result {
    let responseHeaders = headers ?? [:]

    return TranscriptionModelV3Result(
        text: text,
        segments: segments.map {
            TranscriptionModelV3Result.Segment(
                text: $0.text,
                startSecond: $0.startSecond,
                endSecond: $0.endSecond
            )
        },
        language: language,
        durationInSeconds: durationInSeconds,
        warnings: warnings.map(convertTranscriptionWarningToV3),
        request: nil,
        response: TranscriptionModelV3Result.ResponseInfo(
            timestamp: timestamp,
            modelId: modelId,
            headers: responseHeaders,
            body: nil
        ),
        providerMetadata: providerMetadata
    )
}

private func makeMockResponseV4(
    text: String = sampleTranscriptText,
    segments: [TranscriptionModelV4Result.Segment] = sampleSegments,
    language: String? = sampleLanguage,
    durationInSeconds: Double? = sampleDuration,
    warnings: [TranscriptionWarning] = [],
    timestamp: Date = Date(),
    modelId: String = "test-model-id",
    headers: [String: String]? = nil,
    providerMetadata: [String: [String: JSONValue]]? = nil
) -> TranscriptionModelV4Result {
    let responseHeaders = headers ?? [:]

    return TranscriptionModelV4Result(
        text: text,
        segments: segments,
        language: language,
        durationInSeconds: durationInSeconds,
        warnings: warnings,
        request: nil,
        response: TranscriptionModelV4Result.ResponseInfo(
            timestamp: timestamp,
            modelId: modelId,
            headers: responseHeaders,
            body: nil
        ),
        providerMetadata: providerMetadata
    )
}

private func convertTranscriptionWarningToV3(_ warning: TranscriptionWarning) -> SharedV3Warning {
    switch warning {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .deprecated(let setting, let message):
        return .other(message: "The setting \"\(setting)\" is deprecated - \(message)")
    case .other(let message):
        return .other(message: message)
    }
}

@Suite(.serialized)
struct TranscribeTests {
    @Test("should send args to doGenerate")
    func shouldSendArgsToDoGenerate() async throws {
        let abortCalled = ValueBox(false)
        let abortSignal: @Sendable () -> Bool = {
            abortCalled.value = true
            return false
        }

        let capturedOptions = ValueBox<TranscriptionModelV3CallOptions?>(nil)

        let model = MockTranscriptionModelV3 { options in
            capturedOptions.value = options
            return makeMockResponse()
        }

        _ = try await transcribe(
            model: model,
            audio: .data(audioData),
            providerOptions: [:],
            maxRetries: nil,
            abortSignal: abortSignal,
            headers: [
                "custom-request-header": "request-header-value"
            ]
        )

        guard let options = capturedOptions.value else {
            Issue.record("doGenerate was not called")
            return
        }

        switch options.audio {
        case .binary(let data):
            #expect(data == audioData)
        case .base64:
            Issue.record("Expected binary audio data")
        }

        #expect(options.mediaType == "audio/wav")

        let headers = options.headers ?? [:]
        let expectedUserAgent = "ai/\(SwiftAISDK.VERSION)"
        #expect(headers["custom-request-header"] == Optional("request-header-value"))
        #expect(headers["user-agent"] == Optional(expectedUserAgent))

        let providerOptions = options.providerOptions ?? [:]
        #expect(providerOptions.isEmpty)

        #expect(options.abortSignal != nil)
        _ = options.abortSignal?()
        #expect(abortCalled.value == true)
    }

    @Test("should send V4 args directly to doGenerate")
    func shouldSendV4ArgsDirectlyToDoGenerate() async throws {
        let abortCalled = ValueBox(false)
        let abortSignal: @Sendable () -> Bool = {
            abortCalled.value = true
            return false
        }

        let capturedOptions = ValueBox<TranscriptionModelV4CallOptions?>(nil)
        let expectedWarning: TranscriptionWarning = .deprecated(
            setting: "mediaType",
            message: "Use provider options instead"
        )

        let model = MockTranscriptionModelV4 { options in
            capturedOptions.value = options
            return makeMockResponseV4(warnings: [expectedWarning])
        }

        let result = try await transcribe(
            model: model,
            audio: .data(audioData),
            providerOptions: [
                "mock-provider": [
                    "temperature": .number(0)
                ]
            ],
            abortSignal: abortSignal,
            headers: [
                "custom-request-header": "request-header-value"
            ]
        )

        guard let options = capturedOptions.value else {
            Issue.record("doGenerate was not called")
            return
        }

        switch options.audio {
        case .binary(let data):
            #expect(data == audioData)
        case .base64:
            Issue.record("Expected binary audio data")
        }

        #expect(options.mediaType == "audio/wav")
        #expect(options.providerOptions?["mock-provider"]?["temperature"] == .number(0))
        #expect(options.headers?["custom-request-header"] == "request-header-value")
        #expect(options.headers?["user-agent"] == "ai/\(SwiftAISDK.VERSION)")
        #expect(options.abortSignal != nil)
        _ = options.abortSignal?()
        #expect(abortCalled.value == true)
        #expect(result.warnings == [expectedWarning])
    }

    @Test("should download URL audio with custom download function")
    func shouldDownloadURLAudioWithCustomDownloadFunction() async throws {
        let url = URL(string: "https://example.com/audio.wav")!
        let downloadCalled = ValueBox(false)
        let abortCalled = ValueBox(false)
        let capturedOptions = ValueBox<TranscriptionModelV3CallOptions?>(nil)

        let abortSignal: @Sendable () -> Bool = {
            abortCalled.value = true
            return false
        }

        let download: DownloadFileFunction = { request in
            #expect(request.url == url)
            #expect(request.abortSignal?() == false)
            downloadCalled.value = true
            return DownloadResult(data: audioData, mediaType: "audio/wav")
        }

        let model = MockTranscriptionModelV3 { options in
            capturedOptions.value = options
            return makeMockResponse()
        }

        _ = try await transcribe(
            model: model,
            audio: .url(url),
            abortSignal: abortSignal,
            experimentalDownload: download
        )

        #expect(downloadCalled.value == true)
        #expect(abortCalled.value == true)

        guard let options = capturedOptions.value else {
            Issue.record("doGenerate was not called")
            return
        }

        switch options.audio {
        case .binary(let data):
            #expect(data == audioData)
        case .base64:
            Issue.record("Expected binary audio data")
        }
    }

    @Test("should resolve string transcription model IDs through V4 global provider")
    func shouldResolveStringTranscriptionModelThroughV4GlobalProvider() async throws {
        let provider = customProviderV4(
            transcriptionModels: [
                "transcription-model": MockTranscriptionModelV4(
                    provider: "v4-provider",
                    modelId: "resolved-transcription-model",
                    doGenerate: { _ in
                        makeMockResponseV4(modelId: "resolved-transcription-model")
                    }
                )
            ]
        )

        let result = try await withGlobalProviderV4(provider, operation: {
            try await transcribe(
                model: .string("transcription-model"),
                audio: .data(audioData)
            )
        })

        #expect(result.text == sampleTranscriptText)
        #expect(result.responses.first?.modelId == "resolved-transcription-model")
    }

    @Test("should return warnings")
    func shouldReturnWarnings() async throws {
        let warnings: [TranscriptionWarning] = [
            .other(message: "Setting is not supported")
        ]

        let providerMetadata: [String: [String: JSONValue]] = [
            "test-provider": [
                "test-key": .string("test-value")
            ]
        ]

        let model = MockTranscriptionModelV3 { _ in
            makeMockResponse(
                warnings: warnings,
                providerMetadata: providerMetadata
            )
        }

        let result = try await transcribe(
            model: model,
            audio: .data(audioData)
        )

        #expect(result.warnings == warnings)
        #expect(result.providerMetadata["test-provider"]?["test-key"] == .string("test-value"))
    }

    @Test("should call logWarnings with the correct warnings")
    func shouldCallLogWarningsWithExpectedWarnings() async throws {
        try await LogWarningsTestLock.shared.withLock {
            let expectedWarnings: [TranscriptionWarning] = [
                .other(message: "Setting is not supported"),
                .unsupported(feature: "mediaType", details: "MediaType parameter not supported")
            ]

            let previousLogger = logWarningsForTranscribe
            defer { logWarningsForTranscribe = previousLogger }

            let recordedWarnings = ValueBox([[Warning]]())
            logWarningsForTranscribe = { warnings in
                recordedWarnings.value.append(warnings)
            }

            let model = MockTranscriptionModelV3 { _ in
                makeMockResponse(warnings: expectedWarnings)
            }

            _ = try await transcribe(
                model: model,
                audio: .data(audioData)
            )

            let expectedLogged = expectedWarnings.map { Warning.transcriptionModel($0) }
            #expect(recordedWarnings.value.count == 1)
            #expect(recordedWarnings.value.first == expectedLogged)
        }
    }

    @Test("should call logWarnings with empty array when no warnings are present")
    func shouldCallLogWarningsWithEmptyArray() async throws {
        try await LogWarningsTestLock.shared.withLock {
            let previousLogger = logWarningsForTranscribe
            defer { logWarningsForTranscribe = previousLogger }

            let recordedWarnings = ValueBox([[Warning]]())
            logWarningsForTranscribe = { warnings in
                recordedWarnings.value.append(warnings)
            }

            let model = MockTranscriptionModelV3 { _ in
                makeMockResponse(warnings: [])
            }

            _ = try await transcribe(
                model: model,
                audio: .data(audioData)
            )

            #expect(recordedWarnings.value.count == 1)
            #expect(recordedWarnings.value.first?.isEmpty == true)
        }
    }

    @Test("should return the transcript")
    func shouldReturnTranscript() async throws {
        let model = MockTranscriptionModelV3 { _ in
            makeMockResponse()
        }

        let result = try await transcribe(
            model: model,
            audio: .data(audioData)
        )

        #expect(result.text == sampleTranscriptText)
        #expect(result.segments == [
            TranscriptionSegment(text: "This is a", startSecond: 0, endSecond: 2.5),
            TranscriptionSegment(text: "sample transcript.", startSecond: 2.5, endSecond: 4.0)
        ])
        #expect(result.language == sampleLanguage)
        #expect(result.durationInSeconds == sampleDuration)
        #expect(result.warnings.isEmpty)
        #expect(result.responses.count == 1)
        #expect(result.providerMetadata.isEmpty)

        let response = result.responses[0]
        #expect(!response.modelId.isEmpty)
        #expect(response.headers == [:])
    }

    @Test("should throw NoTranscriptGeneratedError when no transcript is returned")
    func shouldThrowWhenNoTranscriptReturned() async throws {
        let model = MockTranscriptionModelV3 { _ in
            makeMockResponse(
                text: "",
                segments: [],
                language: sampleLanguage,
                durationInSeconds: 0,
                timestamp: testDate
            )
        }

        do {
            _ = try await transcribe(
                model: model,
                audio: .data(audioData)
            )
            Issue.record("Expected NoTranscriptGeneratedError to be thrown")
        } catch let error as NoTranscriptGeneratedError {
            #expect(error.name == "AI_NoTranscriptGeneratedError")
            #expect(error.message == "No transcript generated.")
            #expect(error.responses.count == 1)
            let response = error.responses[0]
            #expect(response.timestamp == testDate)
            #expect(!response.modelId.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("should include response headers in error when no transcript generated")
    func shouldIncludeHeadersInError() async throws {
        let expectedUserAgent = "ai/\(SwiftAISDK.VERSION)"
        let responseHeaders: [String: String] = [
            "custom-response-header": "response-header-value",
            "user-agent": expectedUserAgent
        ]

        let model = MockTranscriptionModelV3 { _ in
            makeMockResponse(
                text: "",
                segments: [],
                language: sampleLanguage,
                durationInSeconds: 0,
                warnings: [],
                timestamp: testDate,
                headers: responseHeaders
            )
        }

        do {
            _ = try await transcribe(
                model: model,
                audio: .data(audioData)
            )
            Issue.record("Expected NoTranscriptGeneratedError to be thrown")
        } catch let error as NoTranscriptGeneratedError {
            #expect(error.responses.count == 1)
            let response = error.responses[0]
            #expect(response.headers?["custom-response-header"] == "response-header-value")
            #expect(response.headers?["user-agent"] == expectedUserAgent)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("should return response metadata")
    func shouldReturnResponseMetadata() async throws {
        let testHeaders: [String: String] = ["x-test": "value"]

        let model = MockTranscriptionModelV3 { _ in
            makeMockResponse(
                timestamp: testDate,
                modelId: "test-model",
                headers: testHeaders
            )
        }

        let result = try await transcribe(
            model: model,
            audio: .data(audioData)
        )

        #expect(result.responses.count == 1)
        let response = result.responses[0]
        #expect(response.timestamp == testDate)
        #expect(response.modelId == "test-model")
        #expect(response.headers == testHeaders)
    }
}

private final class MockTranscriptionModelV3: TranscriptionModelV3, @unchecked Sendable {
    let provider: String
    let modelId: String

    private let generate: @Sendable (TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result

    init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        doGenerate: @escaping @Sendable (TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result
    ) {
        self.provider = provider
        self.modelId = modelId
        self.generate = doGenerate
    }

    func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        try await generate(options)
    }
}
