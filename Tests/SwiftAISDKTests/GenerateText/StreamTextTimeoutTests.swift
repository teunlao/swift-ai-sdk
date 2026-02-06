import Foundation
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
import Testing

@Suite("StreamText – timeout")
struct StreamTextTimeoutTests {
    private func makeStream() -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(),
                providerMetadata: nil
            ),
        ]

        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }

    @Test("timeout forwards abort signal to model")
    func timeoutForwardsAbortSignalToModel() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeStream()))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: 5000)
        )

        await result.consumeStream()

        #expect(model.doStreamCalls.count == 1)
        #expect(model.doStreamCalls.first?.abortSignal != nil)
    }

    @Test("no timeout and no abortSignal passes nil to model")
    func noTimeoutPassesNilAbortSignalToModel() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeStream()))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input"
        )

        await result.consumeStream()

        #expect(model.doStreamCalls.count == 1)
        #expect(model.doStreamCalls.first?.abortSignal == nil)
    }

    @Test("timeout object without totalMs/stepMs/chunkMs does not create abort signal")
    func emptyTimeoutObjectDoesNotCreateAbortSignal() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeStream()))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: .configuration())
        )

        await result.consumeStream()

        #expect(model.doStreamCalls.count == 1)
        #expect(model.doStreamCalls.first?.abortSignal == nil)
    }

    @Test("stepMs creates abort signal")
    func stepTimeoutCreatesAbortSignal() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeStream()))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: .configuration(stepMs: 5000))
        )

        await result.consumeStream()

        #expect(model.doStreamCalls.count == 1)
        #expect(model.doStreamCalls.first?.abortSignal != nil)
    }

    @Test("chunkMs creates abort signal")
    func chunkTimeoutCreatesAbortSignal() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeStream()))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: .configuration(chunkMs: 5000))
        )

        await result.consumeStream()

        #expect(model.doStreamCalls.count == 1)
        #expect(model.doStreamCalls.first?.abortSignal != nil)
    }
}
