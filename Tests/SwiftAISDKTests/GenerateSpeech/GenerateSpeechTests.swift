/**
 Tests for generateSpeech API.

 Port of `@ai-sdk/ai/src/generate-speech/generate-speech.test.ts`.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let audioData = Data([1, 2, 3, 4])
private let mockAudioFile = DefaultGeneratedAudioFile(
    data: audioData,
    mediaType: "audio/mp3"
)
private let sampleText = "This is a sample text to convert to speech."

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

private func makeMockResult(
    audio file: DefaultGeneratedAudioFile,
    warnings: [SpeechModelV3CallWarning] = [],
    timestamp: Date = Date(),
    modelId: String = "test-model-id",
    headers: [String: String]? = nil,
    providerMetadata: [String: [String: JSONValue]]? = nil
) -> SpeechModelV3Result {
    SpeechModelV3Result(
        audio: .binary(file.data),
        warnings: warnings,
        request: nil,
        response: SpeechModelV3Result.ResponseInfo(
            timestamp: timestamp,
            modelId: modelId,
            headers: headers,
            body: nil
        ),
        providerMetadata: providerMetadata
    )
}

@Suite(.serialized)
struct GenerateSpeechTests {
    @Test("should send args to doGenerate")
    func shouldSendArgsToDoGenerate() async throws {
        let abortCalled = ValueBox(false)
        let abortSignal: @Sendable () -> Bool = {
            abortCalled.value = true
            return false
        }

        let capturedOptions = ValueBox<SpeechModelV3CallOptions?>(nil)

        let model = MockSpeechModelV3 { options in
            capturedOptions.value = options
            return makeMockResult(audio: mockAudioFile)
        }

        _ = try await generateSpeech(
            model: model,
            text: sampleText,
            voice: "test-voice",
            abortSignal: abortSignal,
            headers: [
                "custom-request-header": "request-header-value"
            ]
        )

        guard let options = capturedOptions.value else {
            Issue.record("doGenerate was not called")
            return
        }

        #expect(options.text == sampleText)
        #expect(options.voice == "test-voice")
        #expect(options.outputFormat == nil)
        #expect(options.instructions == nil)
        #expect(options.speed == nil)
        #expect(options.language == nil)

        let headers = options.headers ?? [:]
        let expectedUserAgent: String = "ai/\(SwiftAISDK.VERSION)"
        #expect(headers["custom-request-header"] == Optional("request-header-value"))
        #expect(headers["user-agent"] ?? "" == expectedUserAgent)

        let providerOptions = options.providerOptions ?? [:]
        #expect(providerOptions.isEmpty)

        #expect(options.abortSignal != nil)
        _ = options.abortSignal?()
        #expect(abortCalled.value == true)
    }

    @Test("should return warnings")
    func shouldReturnWarnings() async throws {
        let warnings: [SpeechModelV3CallWarning] = [
            .other(message: "Setting is not supported")
        ]

        let providerMetadata: [String: [String: JSONValue]] = [
            "test-provider": [
                "test-key": .string("test-value")
            ]
        ]

        let model = MockSpeechModelV3 { _ in
            makeMockResult(
                audio: mockAudioFile,
                warnings: warnings,
                providerMetadata: providerMetadata
            )
        }

        let result = try await generateSpeech(
            model: model,
            text: sampleText
        )

        #expect(result.warnings == warnings)
        #expect(result.providerMetadata["test-provider"]?["test-key"] == .string("test-value"))
    }

    @Test("should call logWarnings with the correct warnings")
    func shouldCallLogWarningsWithWarnings() async throws {
        let expectedWarnings: [SpeechModelV3CallWarning] = [
            .other(message: "Setting is not supported"),
            .unsupportedSetting(setting: "voice", details: "Voice parameter not supported")
        ]

        let previousLogger = logWarningsForGenerateSpeech
        defer { logWarningsForGenerateSpeech = previousLogger }

        let recordedWarnings = ValueBox([[Warning]]())
        logWarningsForGenerateSpeech = { warnings in
            recordedWarnings.value.append(warnings)
        }

        let model = MockSpeechModelV3 { _ in
            makeMockResult(audio: mockAudioFile, warnings: expectedWarnings)
        }

        _ = try await generateSpeech(
            model: model,
            text: sampleText
        )

        #expect(recordedWarnings.value.count == 1)
        let expectedLogged = expectedWarnings.map { Warning.speechModel($0) }
        #expect(recordedWarnings.value.first == expectedLogged)
    }

    @Test("should call logWarnings with empty array when no warnings are present")
    func shouldCallLogWarningsWithEmptyArray() async throws {
        let previousLogger = logWarningsForGenerateSpeech
        defer { logWarningsForGenerateSpeech = previousLogger }

        let recordedWarnings = ValueBox<[Warning]?>(nil)
        logWarningsForGenerateSpeech = { warnings in
            recordedWarnings.value = warnings
        }

        let model = MockSpeechModelV3 { _ in
            makeMockResult(audio: mockAudioFile, warnings: [])
        }

        _ = try await generateSpeech(
            model: model,
            text: sampleText
        )

        #expect(recordedWarnings.value?.isEmpty == true)
    }

    @Test("should return the audio data")
    func shouldReturnAudioData() async throws {
        let model = MockSpeechModelV3 { _ in
            makeMockResult(audio: mockAudioFile)
        }

        let result = try await generateSpeech(
            model: model,
            text: sampleText
        )

        #expect(result.audio.mediaType == "audio/mp3")
        #expect(result.audio.data == audioData)
        #expect(result.warnings.isEmpty)
        #expect(result.responses.count == 1)
        #expect(result.providerMetadata.isEmpty)
    }

    @Test("should throw NoSpeechGeneratedError when no audio is returned")
    func shouldThrowWhenNoAudio() async {
        let emptyFile = DefaultGeneratedAudioFile(
            data: Data(),
            mediaType: "audio/mp3"
        )

        let model = MockSpeechModelV3 { _ in
            makeMockResult(
                audio: emptyFile,
                timestamp: testDate
            )
        }

        do {
            _ = try await generateSpeech(
                model: model,
                text: sampleText
            )
            Issue.record("Expected NoSpeechGeneratedError to be thrown")
        } catch let error as NoSpeechGeneratedError {
            #expect(error.name == "AI_NoSpeechGeneratedError")
            #expect(error.message == "No speech audio generated.")
            #expect(error.responses.count == 1)
            let response = error.responses[0]
            #expect(response.timestamp == testDate)
            #expect(!response.modelId.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("should include response headers in error when no audio generated")
    func shouldIncludeHeadersInError() async {
        let emptyFile = DefaultGeneratedAudioFile(
            data: Data(),
            mediaType: "audio/mp3"
        )

        let expectedUserAgent: String = "ai/\(SwiftAISDK.VERSION)"
        let headers: [String: String] = [
            "custom-response-header": "response-header-value",
            "user-agent": expectedUserAgent
        ]

        let model = MockSpeechModelV3 { _ in
            makeMockResult(
                audio: emptyFile,
                timestamp: testDate,
                headers: headers
            )
        }

        do {
            _ = try await generateSpeech(
                model: model,
                text: sampleText
            )
            Issue.record("Expected NoSpeechGeneratedError to be thrown")
        } catch let error as NoSpeechGeneratedError {
            #expect(error.responses.count == 1)
            let response = error.responses[0]
            #expect(response.headers?["custom-response-header"] == Optional("response-header-value"))
            let actualUserAgent = response.headers?["user-agent"] ?? ""
            #expect(actualUserAgent == expectedUserAgent)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("should return response metadata")
    func shouldReturnResponseMetadata() async throws {
        let headers = ["x-test": "value"]

        let model = MockSpeechModelV3 { _ in
            makeMockResult(
                audio: mockAudioFile,
                timestamp: testDate,
                modelId: "test-model",
                headers: headers
            )
        }

        let result = try await generateSpeech(
            model: model,
            text: sampleText
        )

        #expect(result.responses.count == 1)
        let response = result.responses[0]
        #expect(response.timestamp == testDate)
        #expect(response.modelId == "test-model")
        #expect(response.headers?["x-test"] == "value")
    }
}

// MARK: - Mock Speech Model

private final class MockSpeechModelV3: SpeechModelV3, @unchecked Sendable {
    let specificationVersion: String
    let provider: String
    let modelId: String

    private let generateHandler: @Sendable (SpeechModelV3CallOptions) async throws -> SpeechModelV3Result

    init(
        specificationVersion: String = "v3",
        provider: String = "mock-provider",
        modelId: String = "test-model-id",
        doGenerate: @escaping @Sendable (SpeechModelV3CallOptions) async throws -> SpeechModelV3Result
    ) {
        self.specificationVersion = specificationVersion
        self.provider = provider
        self.modelId = modelId
        self.generateHandler = doGenerate
    }

    func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        try await generateHandler(options)
    }
}
