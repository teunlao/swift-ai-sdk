import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let streamAudioData = Data([1, 2, 3])
private let streamInputAudioFormat = TranscriptionModelV4StreamOptions.InputAudioFormat(type: "audio/pcm", rate: 16_000)

private let streamTestDate: Date = {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2024
    components.month = 1
    components.day = 1
    return components.date!
}()

private final class StreamValueBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

private func makeTranscriptionAudioStream(
    _ audio: [TranscriptionModelV4StreamAudio] = [.binary(streamAudioData)]
) -> AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
    convertArrayToReadableStream(audio)
}

private func makeStreamResult(
    _ parts: [TranscriptionModelV4StreamPart],
    timestamp: Date? = streamTestDate,
    modelId: String? = "test-model-id",
    headers: [String: String]? = ["x-test": "value"]
) -> TranscriptionModelV4StreamResult {
    TranscriptionModelV4StreamResult(
        stream: convertArrayToReadableStream(parts),
        response: .init(timestamp: timestamp, modelId: modelId, headers: headers)
    )
}

@Suite(.serialized)
struct StreamTranscribeTests {
    @Test("experimental_streamTranscribe sends args to doStream")
    func sendsArgsToDoStream() async throws {
        let abortCalled = StreamValueBox(false)
        let abortSignal: @Sendable () -> Bool = {
            abortCalled.value = true
            return false
        }

        let capturedOptions = StreamValueBox<TranscriptionModelV4StreamOptions?>(nil)
        let capturedAudio = StreamValueBox<[TranscriptionModelV4StreamAudio]>([])

        let model = MockTranscriptionModelV4(doStream: { options in
            capturedOptions.value = options
            capturedAudio.value = try await convertAsyncIterableToArray(options.audio)
            return makeStreamResult([
                .streamStart(warnings: []),
                .finish(text: "Hello world", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil)
            ])
        })

        let result = try experimental_streamTranscribe(
            model: model,
            audio: makeTranscriptionAudioStream(),
            inputAudioFormat: streamInputAudioFormat,
            providerOptions: ["mock": ["option": .string("value")]],
            abortSignal: abortSignal,
            headers: ["custom-request-header": "request-header-value"],
            includeRawChunks: true
        )

        _ = try await convertAsyncIterableToArray(result.fullStream)

        let options = try #require(capturedOptions.value)
        #expect(capturedAudio.value == [.binary(streamAudioData)])
        #expect(options.inputAudioFormat == streamInputAudioFormat)
        #expect(options.providerOptions?["mock"]?["option"] == .string("value"))
        #expect(options.headers?["custom-request-header"] == "request-header-value")
        #expect(options.headers?["user-agent"] == "ai/\(SwiftAISDK.VERSION)")
        #expect(options.includeRawChunks == true)
        #expect(options.abortSignal != nil)
        _ = options.abortSignal?()
        #expect(abortCalled.value == true)
    }

    @Test("streamTranscribe streams transcript parts and resolves final metadata")
    func streamsTranscriptPartsAndResolvesFinalMetadata() async throws {
        let model = MockTranscriptionModelV4(doStream: { _ in
            makeStreamResult([
                .streamStart(warnings: [.other(message: "test warning")]),
                .responseMetadata(timestamp: nil, modelId: "stream-model-id", headers: ["x-stream": "ok"], body: nil),
                .transcriptDelta(id: "item-1", delta: "Hel", providerMetadata: nil),
                .transcriptDelta(id: "item-1", delta: "lo", providerMetadata: nil),
                .transcriptFinal(
                    id: "item-1",
                    text: "Hello",
                    startSecond: 0,
                    endSecond: 1,
                    channelIndex: nil,
                    providerMetadata: ["mock": ["chunk": .string("final")]]
                ),
                .raw(rawValue: ["type": "raw"]),
                .error(error: ["message": "soft error"]),
                .finish(
                    text: "Hello",
                    segments: [.init(text: "Hello", startSecond: 0, endSecond: 1)],
                    language: "en",
                    durationInSeconds: 1,
                    providerMetadata: ["mock": ["key": .string("value")]]
                )
            ])
        })

        let result = try streamTranscribe(
            model: model,
            audio: makeTranscriptionAudioStream(),
            inputAudioFormat: streamInputAudioFormat
        )

        let parts = try await convertAsyncIterableToArray(result.fullStream)
        #expect(parts == [
            .transcriptDelta(id: "item-1", delta: "Hel", providerMetadata: nil),
            .transcriptDelta(id: "item-1", delta: "lo", providerMetadata: nil),
            .transcriptFinal(
                id: "item-1",
                text: "Hello",
                startSecond: 0,
                endSecond: 1,
                channelIndex: nil,
                providerMetadata: ["mock": ["chunk": .string("final")]]
            ),
            .raw(rawValue: ["type": "raw"]),
            .error(error: ["message": "soft error"])
        ])

        #expect(try await result.text == "Hello")
        #expect(try await result.segments == [
            TranscriptionSegment(text: "Hello", startSecond: 0, endSecond: 1)
        ])
        #expect(try await result.language == "en")
        #expect(try await result.durationInSeconds == 1)
        #expect(try await result.warnings == [.other(message: "test warning")])
        #expect(try await result.providerMetadata["mock"]?["key"] == .string("value"))

        let responses = try await result.responses
        #expect(responses.count == 1)
        #expect(responses.first?.timestamp == streamTestDate)
        #expect(responses.first?.modelId == "stream-model-id")
        #expect(responses.first?.headers?["x-stream"] == "ok")
    }

    @Test("streamTranscribe rejects final promises when no transcript is returned")
    func rejectsWhenNoTranscriptIsReturned() async throws {
        let model = MockTranscriptionModelV4(doStream: { _ in
            makeStreamResult([
                .streamStart(warnings: []),
                .finish(text: "", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil)
            ])
        })

        let result = try streamTranscribe(
            model: model,
            audio: makeTranscriptionAudioStream(),
            inputAudioFormat: streamInputAudioFormat
        )

        do {
            _ = try await convertAsyncIterableToArray(result.fullStream)
            Issue.record("Expected fullStream to throw NoTranscriptGeneratedError")
        } catch let error as NoTranscriptGeneratedError {
            #expect(error.name == "AI_NoTranscriptGeneratedError")
            #expect(error.responses.first?.timestamp == streamTestDate)
            #expect(error.responses.first?.modelId == "test-model-id")
        }

        do {
            _ = try await result.text
            Issue.record("Expected text promise to reject")
        } catch let error as NoTranscriptGeneratedError {
            #expect(error.name == "AI_NoTranscriptGeneratedError")
        }
    }

    @Test("streamTranscribe forwards doStream unsupported errors")
    func forwardsUnsupportedDoStreamErrors() async throws {
        let model = MockTranscriptionModelV4()
        let result = try streamTranscribe(
            model: model,
            audio: makeTranscriptionAudioStream(),
            inputAudioFormat: streamInputAudioFormat
        )

        do {
            _ = try await convertAsyncIterableToArray(result.fullStream)
            Issue.record("Expected unsupported stream to throw")
        } catch is NotImplementedError {
            return
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
