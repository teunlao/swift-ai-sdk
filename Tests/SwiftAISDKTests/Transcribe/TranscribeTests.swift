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

private let sampleSegments: [TranscriptionModelV3Result.Segment] = [
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
    segments: [TranscriptionModelV3Result.Segment] = sampleSegments,
    language: String? = sampleLanguage,
    durationInSeconds: Double? = sampleDuration,
    warnings: [TranscriptionModelV3CallWarning] = [],
    timestamp: Date = Date(),
    modelId: String = "test-model-id",
    headers: [String: String]? = nil,
    providerMetadata: [String: [String: JSONValue]]? = nil
) -> TranscriptionModelV3Result {
    let responseHeaders = headers ?? [:]

    return TranscriptionModelV3Result(
        text: text,
        segments: segments,
        language: language,
        durationInSeconds: durationInSeconds,
        warnings: warnings,
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

    @Test("should return warnings")
    func shouldReturnWarnings() async throws {
        let warnings: [TranscriptionModelV3CallWarning] = [
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
            let expectedWarnings: [TranscriptionModelV3CallWarning] = [
                .other(message: "Setting is not supported"),
                .unsupportedSetting(setting: "mediaType", details: "MediaType parameter not supported")
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
    func shouldThrowWhenNoTranscriptReturned() async {
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
    func shouldIncludeHeadersInError() async {
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
