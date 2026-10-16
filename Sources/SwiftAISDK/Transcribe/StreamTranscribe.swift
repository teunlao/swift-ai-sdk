import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streams transcripts using a transcription model.

 Port of `@ai-sdk/ai/src/transcribe/stream-transcribe.ts`.
 */
public func streamTranscribe(
    model: TranscriptionModel,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil,
    telemetry: TelemetryOptions? = nil
) throws -> any StreamTranscriptionResult {
    guard let resolvedModel = try resolveTranscriptionModelV4(model) else {
        throw ModelResolutionFailure(message: "Model could not be resolved")
    }
    return makeStreamTranscriptionResult(
        model: resolvedModel,
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks,
        telemetry: telemetry
    )
}

public func streamTranscribe(
    model: any TranscriptionModelV4,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil,
    telemetry: TelemetryOptions? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: .v4(model),
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks,
        telemetry: telemetry
    )
}

public func streamTranscribe(
    model: any TranscriptionModelV3,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil,
    telemetry: TelemetryOptions? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: .v3(model),
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks,
        telemetry: telemetry
    )
}

private func makeStreamTranscriptionResult(
    model: any TranscriptionModelV4,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String]?,
    includeRawChunks: Bool?,
    telemetry: TelemetryOptions?
) -> any StreamTranscriptionResult {
    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let callId = (try? createIDGenerator(prefix: "call", size: 24))?() ?? UUID().uuidString
    let dispatcher = TelemetryDispatcher(telemetry: telemetry)
    let telemetryState = StreamTranscriptionTelemetryState()
    let audioFormatMediaType = inputAudioFormat.type
    let audio = dispatcher.isActive ? countingAudioBytes(audio, into: telemetryState) : audio
    let startEvent = StreamTranscriptionStartEvent(
        callId: callId, operationId: "ai.streamTranscribe",
        provider: model.provider, modelId: model.modelId,
        audio: .init(byteLength: nil, mediaType: audioFormatMediaType),
        inputAudioFormat: inputAudioFormat, maxRetries: nil,
        headers: headers, providerOptions: providerOptions
    )

    let textPromise = DelayedPromise<String>()
    let segmentsPromise = DelayedPromise<[TranscriptionSegment]>()
    let languagePromise = DelayedPromise<String?>()
    let durationInSecondsPromise = DelayedPromise<Double?>()
    let warningsPromise = DelayedPromise<[TranscriptionWarning]>()
    let responsesPromise = DelayedPromise<[TranscriptionModelResponseMetadata]>()
    let providerMetadataPromise = DelayedPromise<[String: JSONObject]>()

    let rejectPending: @Sendable (any Error) -> Void = { error in
        for promise in [
            textPromise,
            segmentsPromise,
            languagePromise,
            durationInSecondsPromise,
            warningsPromise,
            responsesPromise,
            providerMetadataPromise
        ] as [AnyDelayedPromise] {
            promise.rejectIfPending(error)
        }
        if telemetryState.settle() {
            Task { await dispatcher.onError(callId: callId, error: error) }
        }
    }

    let resolveWarnings: @Sendable ([TranscriptionWarning]) -> Void = { warnings in
        telemetryState.setWarnings(warnings)
        warningsPromise.resolve(warnings)
        logWarningsForTranscribe(warnings.map { Warning.transcriptionModel($0) })
    }

    let cancellation = StreamTranscriptionCancellation()
    let startedAt = Date()
    let state = StreamTranscribeState(audio: audio, startedAt: startedAt, modelId: model.modelId,
                                     resolveWarnings: resolveWarnings, warningsPending: { warningsPromise.isPending() },
                                     textPending: { textPromise.isPending() }, rejectPending: rejectPending,
                                     resolveFinish: { text, segments, language, duration, usage, metadata, response in
        let segments = segments.map {
            TranscriptionSegment(text: $0.text, startSecond: $0.startSecond, endSecond: $0.endSecond)
        }
        textPromise.resolve(text)
        segmentsPromise.resolve(segments)
        languagePromise.resolve(language)
        durationInSecondsPromise.resolve(duration)
        responsesPromise.resolve([response])
        providerMetadataPromise.resolve(metadata ?? [:])

        guard telemetryState.settle() else { return }
        await dispatcher.onStreamTranscriptionEnd(StreamTranscriptionEndEvent(
            callId: callId, operationId: "ai.streamTranscribe",
            provider: model.provider, modelId: model.modelId,
            audio: .init(byteLength: telemetryState.audioByteLength, mediaType: audioFormatMediaType),
            text: text, segments: segments, language: language, durationInSeconds: duration,
            usage: usage, warnings: telemetryState.warnings, providerMetadata: metadata,
            response: response
        ))
    })
    Task {
        await dispatcher.onStreamTranscriptionStart(startEvent)
        await state.start(model: model, options: TranscriptionModelV4StreamOptions(
            audio: audio, inputAudioFormat: inputAudioFormat, providerOptions: providerOptions,
            abortSignal: { cancellation.isCancelled || abortSignal?() == true },
            headers: headersWithUserAgent, includeRawChunks: includeRawChunks
        ))
    }
    let stream = AsyncIterableStream<TranscriptionStreamPart>(unfolding: { try await state.next() }, onCancel: { reason in
        cancellation.cancel()
        await state.cancel(reason)
    })
    return DefaultStreamTranscriptionResult(
        textPromise: textPromise, segmentsPromise: segmentsPromise, languagePromise: languagePromise,
        durationInSecondsPromise: durationInSecondsPromise, warningsPromise: warningsPromise,
        responsesPromise: responsesPromise, providerMetadataPromise: providerMetadataPromise,
        fullStream: stream
    )
}

private protocol AnyDelayedPromise: Sendable {
    func rejectIfPending(_ error: any Error)
}

extension DelayedPromise: AnyDelayedPromise {
    fileprivate func rejectIfPending(_ error: any Error) {
        if isPending() {
            reject(error)
        }
    }
}

/// Telemetry facts of one streaming transcription; it settles once, by finish or by failure.
private final class StreamTranscriptionTelemetryState: @unchecked Sendable {
    private let lock = NSLock()
    private var settled = false
    private var byteLength = 0
    private var resolvedWarnings: [TranscriptionWarning] = []

    func settle() -> Bool {
        lock.withLock {
            defer { settled = true }
            return !settled
        }
    }

    func addAudioBytes(_ count: Int) { lock.withLock { byteLength += count } }
    var audioByteLength: Int { lock.withLock { byteLength } }

    func setWarnings(_ warnings: [TranscriptionWarning]) { lock.withLock { resolvedWarnings = warnings } }
    var warnings: [TranscriptionWarning] { lock.withLock { resolvedWarnings } }
}

/// Passes the audio through on demand while counting its decoded bytes.
private func countingAudioBytes(
    _ audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    into state: StreamTranscriptionTelemetryState
) -> AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
    let iterator = AudioIteratorBox(audio.makeAsyncIterator())
    return AsyncThrowingStream {
        guard let chunk = try await iterator.next() else { return nil }
        switch chunk {
        case .binary(let data):
            state.addAudioBytes(data.count)
        case .base64(let base64):
            state.addAudioBytes(Data(base64Encoded: base64, options: .ignoreUnknownCharacters)?.count ?? 0)
        }
        return chunk
    }
}

private final class AudioIteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.AsyncIterator

    init(_ iterator: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.AsyncIterator) {
        self.iterator = iterator
    }

    func next() async throws -> TranscriptionModelV4StreamAudio? {
        try await iterator.next()
    }
}

private final class StreamTranscriptionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

private actor StreamTranscribeState {
    private enum Startup { case pending, ready, failed(Error) }
    private var startup: Task<Void, Never>?
    private var startupStatus: Startup = .pending
    private var startupWaiters: [CheckedContinuation<Void, Error>] = []
    private let audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>
    private var stream: AsyncIterableStream<TranscriptionModelV4StreamPart>?
    private var iterator: AsyncIterableStream<TranscriptionModelV4StreamPart>.AsyncIterator?
    private var response: TranscriptionModelResponseMetadata
    private var cancelled = false
    private let resolveWarnings: @Sendable ([TranscriptionWarning]) -> Void
    private let warningsPending: @Sendable () -> Bool
    private let textPending: @Sendable () -> Bool
    private let rejectPending: @Sendable (Error) -> Void
    private let resolveFinish: @Sendable (
        String, [TranscriptionModelV4Result.Segment], String?, Double?, JSONObject?, ProviderMetadata?,
        TranscriptionModelResponseMetadata
    ) async -> Void

    init(
        audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>, startedAt: Date, modelId: String,
        resolveWarnings: @escaping @Sendable ([TranscriptionWarning]) -> Void,
        warningsPending: @escaping @Sendable () -> Bool, textPending: @escaping @Sendable () -> Bool,
        rejectPending: @escaping @Sendable (Error) -> Void,
        resolveFinish: @escaping @Sendable (
            String, [TranscriptionModelV4Result.Segment], String?, Double?, JSONObject?, ProviderMetadata?,
            TranscriptionModelResponseMetadata
        ) async -> Void
    ) {
        self.audio = audio
        response = TranscriptionModelResponseMetadata(timestamp: startedAt, modelId: modelId)
        self.resolveWarnings = resolveWarnings
        self.warningsPending = warningsPending
        self.textPending = textPending
        self.rejectPending = rejectPending
        self.resolveFinish = resolveFinish
    }

    func start(model: any TranscriptionModelV4, options: TranscriptionModelV4StreamOptions) {
        guard !cancelled else { return }
        startup = Task {
            do { await accept(try await model.doStream(options: options)) }
            catch {
                startupStatus = .failed(error)
                rejectPending(error)
                settleStartup(error)
                startup = nil
                await cancelStream(audio)
            }
        }
    }

    private func accept(_ result: TranscriptionModelV4StreamResult) async {
        guard !cancelled else { await cancelStream(result.stream); return }
        response = TranscriptionModelResponseMetadata(
            timestamp: result.response?.timestamp ?? response.timestamp,
            modelId: result.response?.modelId ?? response.modelId, headers: result.response?.headers
        )
        let stream = asAsyncIterableStream(source: result.stream)
        self.stream = stream
        iterator = stream.makeAsyncIterator()
        startupStatus = .ready
        startup = nil
        settleStartup(nil)
    }

    private func waitForStartup() async throws {
        switch startupStatus {
        case .ready: return
        case .failed(let error): throw error
        case .pending: try await withCheckedThrowingContinuation { startupWaiters.append($0) }
        }
    }

    private func settleStartup(_ error: Error?) {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) }
            else { waiter.resume() }
        }
    }

    func next() async throws -> TranscriptionStreamPart? {
        do {
            try await waitForStartup()
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            while let part = try await iterator?.next() {
                try Task.checkCancellation()
                switch part {
                case .streamStart(let warnings):
                    resolveWarnings(warnings)
                case .responseMetadata(let timestamp, let modelId, let headers, _):
                    response = TranscriptionModelResponseMetadata(
                        timestamp: timestamp ?? response.timestamp, modelId: modelId ?? response.modelId,
                        headers: headers ?? response.headers
                    )
                case .transcriptDelta(let id, let delta, let metadata):
                    return .transcriptDelta(id: id, delta: delta, providerMetadata: metadata)
                case .transcriptPartial(let id, let text, let start, let duration, let channel, let metadata):
                    return .transcriptPartial(id: id, text: text, startSecond: start,
                                              durationInSeconds: duration, channelIndex: channel, providerMetadata: metadata)
                case .transcriptFinal(let id, let text, let start, let end, let channel, let metadata):
                    return .transcriptFinal(id: id, text: text, startSecond: start,
                                            endSecond: end, channelIndex: channel, providerMetadata: metadata)
                case .raw(let value): return .raw(rawValue: value)
                case .error(let error): return .error(error: error)
                case .finish(let text, let segments, let language, let duration, let usage, let metadata):
                    if warningsPending() { resolveWarnings([]) }
                    guard !text.isEmpty else { throw NoTranscriptGeneratedError(responses: [response]) }
                    await resolveFinish(text, segments, language, duration, usage, metadata, response)
                }
            }
            try Task.checkCancellation()
            if textPending() { throw NoTranscriptGeneratedError(responses: [response]) }
            return nil
        } catch {
            rejectPending(error)
            await stream?.cancel(.error(AnySendableError(error)))
            await cancelStream(audio)
            throw error
        }
    }

    func cancel(_ reason: AsyncIterableStreamCancellationReason) async {
        guard !cancelled else { return }
        cancelled = true
        let error: Error
        switch reason {
        case .none: error = CancellationError()
        case .message: error = AsyncIterableStreamCancelledError(reason: reason)
        case .error(let wrapped): error = wrapped.underlying
        }
        rejectPending(error)
        startupStatus = .failed(error)
        settleStartup(error)
        startup?.cancel()
        startup = nil
        if let stream { await stream.cancel(reason) }
        iterator = nil
        stream = nil
        await cancelStream(audio)
    }
}
