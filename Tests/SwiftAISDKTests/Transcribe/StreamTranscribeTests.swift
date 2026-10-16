import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

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

        let result = try streamTranscribe(
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

    @Test("result getters claim and drain the unclaimed stream")
    func resultGetterClaimsStream() async throws {
        let model = MockTranscriptionModelV4(doStream: { _ in makeStreamResult([
            .raw(rawValue: ["data": "raw"]),
            .transcriptDelta(id: nil, delta: "Hello", providerMetadata: nil),
            .finish(text: "Hello", segments: [], language: "en", durationInSeconds: 1, providerMetadata: nil)
        ]) })
        let result = try streamTranscribe(model: model, audio: makeTranscriptionAudioStream(), inputAudioFormat: streamInputAudioFormat)
        #expect(try await result.text == "Hello")
        #expect(try await result.language == "en")
        do { _ = try result.fullStream; Issue.record("Full stream was available after results claimed it") }
        catch let error as StreamTranscriptionAccessError { #expect(error == .resultAlreadyAccessed) }
    }

    @Test("fullStream can be claimed once while final results remain available")
    func fullStreamSingleOwner() async throws {
        let model = MockTranscriptionModelV4(doStream: { _ in makeStreamResult([
            .raw(rawValue: ["data": "raw"]),
            .finish(text: "Hello", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil)
        ]) })
        let result = try streamTranscribe(model: model, audio: makeTranscriptionAudioStream(), inputAudioFormat: streamInputAudioFormat)
        let stream = try result.fullStream
        do { _ = try result.fullStream; Issue.record("Full stream was claimed twice") }
        catch let error as StreamTranscriptionAccessError { #expect(error == .fullStreamAlreadyAccessed) }
        #expect(try await convertAsyncIterableToArray(stream) == [.raw(rawValue: ["data": "raw"])])
        #expect(try await result.text == "Hello")
    }

    @Test("transcription pulls only requested provider output")
    func providerBackpressure() async throws {
        let source = TranscriptionPulls([
            .raw(rawValue: ["index": 1]), .raw(rawValue: ["index": 2]),
            .finish(text: "Hello", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil)
        ])
        let model = MockTranscriptionModelV4(doStream: { _ in
            TranscriptionModelV4StreamResult(stream: AsyncThrowingStream(unfolding: { source.next() }))
        })
        let result = try streamTranscribe(model: model, audio: makeTranscriptionAudioStream(),
                                          inputAudioFormat: streamInputAudioFormat, includeRawChunks: false)
        let stream = try result.fullStream
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == .raw(rawValue: ["index": 1]))
        await stream.cancel()
        #expect(source.count == 1)
    }

    @Test("early exit cancels both provider output and input audio")
    func earlyExitCancellation() async throws {
        let output = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.makeStream()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let outputCancelled = TranscriptionSignal()
        let audioCancelled = TranscriptionSignal()
        output.continuation.onTermination = { _ in outputCancelled.signal() }
        audio.continuation.onTermination = { _ in audioCancelled.signal() }
        let model = MockTranscriptionModelV4(doStream: { _ in TranscriptionModelV4StreamResult(stream: output.stream) })
        let result = try streamTranscribe(model: model, audio: audio.stream, inputAudioFormat: streamInputAudioFormat)
        let stream = try result.fullStream
        output.continuation.yield(.transcriptDelta(id: nil, delta: "first", providerMetadata: nil))
        #expect(try await firstTranscriptionPart(stream) == .transcriptDelta(id: nil, delta: "first", providerMetadata: nil))
        try await transcriptionBounded { await outputCancelled.wait(); await audioCancelled.wait() }
        do { _ = try await result.text; Issue.record("Cancelled transcription resolved successfully") }
        catch { #expect(error is CancellationError) }
    }

    @Test("cancellation aborts a still-pending provider startup")
    func cancelsPendingStartup() async throws {
        let startup = AsyncThrowingStream<TranscriptionModelV4StreamResult, Error>.makeStream()
        let started = TranscriptionSignal()
        let cancelled = TranscriptionSignal()
        let abort = TranscriptionAbortProbe()
        startup.continuation.onTermination = { _ in cancelled.signal() }
        let model = MockTranscriptionModelV4(doStream: { options in
            abort.store(options.abortSignal)
            started.signal()
            var iterator = startup.stream.makeAsyncIterator()
            guard let result = try await iterator.next() else { throw CancellationError() }
            return result
        })
        let result = try streamTranscribe(model: model, audio: makeTranscriptionAudioStream(), inputAudioFormat: streamInputAudioFormat)
        let stream = try result.fullStream
        await started.wait()
        await stream.cancel()
        try await transcriptionBounded { await cancelled.wait() }
        #expect(abort.isAborted)
        do { _ = try await result.text; Issue.record("Cancelled startup resolved successfully") }
        catch { #expect(error is CancellationError) }
    }

    @Test("cancellation closes readers and audio before an uncooperative startup returns")
    func cancelsUncooperativeStartup() async throws {
        let startup = PendingTranscriptionStartup()
        let output = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.makeStream()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let audioCancelled = TranscriptionSignal()
        let outputCancelled = TranscriptionSignal()
        let cancelCompleted = TranscriptionSignal()
        audio.continuation.onTermination = { _ in audioCancelled.signal() }
        output.continuation.onTermination = { _ in outputCancelled.signal() }
        let lateResult = TranscriptionModelV4StreamResult(stream: output.stream)
        defer { startup.complete(lateResult) }
        let model = MockTranscriptionModelV4(doStream: { _ in await startup.wait() })
        let result = try streamTranscribe(model: model, audio: audio.stream, inputAudioFormat: streamInputAudioFormat)
        let stream = try result.fullStream
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await startup.entered.wait()
        let cancellation = Task { await stream.cancel(); cancelCompleted.signal() }
        try await transcriptionBounded { await cancelCompleted.wait(); await audioCancelled.wait() }
        #expect(try await consumer.value == nil)
        do { _ = try await result.text; Issue.record("Cancelled startup resolved successfully") }
        catch { #expect(error is CancellationError) }
        startup.complete(lateResult)
        try await transcriptionBounded { await outputCancelled.wait() }
        await cancellation.value
    }

    @Test("startup failure cancels audio that the provider never claimed")
    func startupFailureClosesAudio() async throws {
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let cancelled = TranscriptionSignal()
        let failure = TranscriptionStartupFailure()
        audio.continuation.onTermination = { _ in cancelled.signal() }
        let model = MockTranscriptionModelV4(doStream: { _ in throw failure })
        let result = try streamTranscribe(model: model, audio: audio.stream, inputAudioFormat: streamInputAudioFormat)
        do { _ = try await result.text; Issue.record("Startup failure was discarded") }
        catch { #expect(error as? TranscriptionStartupFailure === failure) }
        try await transcriptionBounded { await cancelled.wait() }
    }
}

private func firstTranscriptionPart(_ stream: AsyncIterableStream<TranscriptionStreamPart>) async throws -> TranscriptionStreamPart? {
    for try await part in stream { return part }
    return nil
}

private final class TranscriptionPulls: @unchecked Sendable {
    private let lock = NSLock()
    private let parts: [TranscriptionModelV4StreamPart]
    private var index = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return index }
    init(_ parts: [TranscriptionModelV4StreamPart]) { self.parts = parts }
    func next() -> TranscriptionModelV4StreamPart? {
        lock.lock()
        defer { lock.unlock() }
        guard index < parts.count else { return nil }
        defer { index += 1 }
        return parts[index]
    }
}

private final class TranscriptionAbortProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var signal: (@Sendable () -> Bool)?
    func store(_ signal: (@Sendable () -> Bool)?) { lock.lock(); self.signal = signal; lock.unlock() }
    var isAborted: Bool { lock.lock(); let signal = signal; lock.unlock(); return signal?() == true }
}

private final class TranscriptionSignal: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func signal() { continuation.yield(()); continuation.finish() }
    func wait() async { for await _ in stream {} }
}

private final class PendingTranscriptionStartup: @unchecked Sendable {
    let entered = TranscriptionSignal()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TranscriptionModelV4StreamResult, Never>?
    func wait() async -> TranscriptionModelV4StreamResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            entered.signal()
        }
    }
    func complete(_ result: TranscriptionModelV4StreamResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private final class TranscriptionStartupFailure: Error, @unchecked Sendable {}
private struct TranscriptionTestTimeout: Error {}

private func transcriptionBounded(_ operation: @escaping @Sendable () async -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { await operation() }
        group.addTask { try await Task.sleep(nanoseconds: 1_000_000_000); throw TranscriptionTestTimeout() }
        try await group.next()
        group.cancelAll()
    }
}
