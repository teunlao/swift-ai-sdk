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
    includeRawChunks: Bool? = nil
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
        includeRawChunks: includeRawChunks
    )
}

public func streamTranscribe(
    model: any TranscriptionModelV4,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: .v4(model),
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks
    )
}

public func streamTranscribe(
    model: any TranscriptionModelV3,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: .v3(model),
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks
    )
}

private func makeStreamTranscriptionResult(
    model: any TranscriptionModelV4,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String]?,
    includeRawChunks: Bool?
) -> any StreamTranscriptionResult {
    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
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
    }

    let resolveWarnings: @Sendable ([TranscriptionWarning]) -> Void = { warnings in
        warningsPromise.resolve(warnings)
        logWarningsForTranscribe(warnings.map { Warning.transcriptionModel($0) })
    }

    let cancellation = StreamTranscriptionCancellation()
    let startedAt = Date()
    let state = StreamTranscribeState(audio: audio, startedAt: startedAt, modelId: model.modelId,
                                     resolveWarnings: resolveWarnings, warningsPending: { warningsPromise.isPending() },
                                     textPending: { textPromise.isPending() }, rejectPending: rejectPending,
                                     resolveFinish: { text, segments, language, duration, metadata, response in
        textPromise.resolve(text)
        segmentsPromise.resolve(segments.map {
            TranscriptionSegment(text: $0.text, startSecond: $0.startSecond, endSecond: $0.endSecond)
        })
        languagePromise.resolve(language)
        durationInSecondsPromise.resolve(duration)
        responsesPromise.resolve([response])
        providerMetadataPromise.resolve(metadata ?? [:])
    })
    Task {
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
        String, [TranscriptionModelV4Result.Segment], String?, Double?, ProviderMetadata?, TranscriptionModelResponseMetadata
    ) -> Void

    init(
        audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>, startedAt: Date, modelId: String,
        resolveWarnings: @escaping @Sendable ([TranscriptionWarning]) -> Void,
        warningsPending: @escaping @Sendable () -> Bool, textPending: @escaping @Sendable () -> Bool,
        rejectPending: @escaping @Sendable (Error) -> Void,
        resolveFinish: @escaping @Sendable (
            String, [TranscriptionModelV4Result.Segment], String?, Double?, ProviderMetadata?, TranscriptionModelResponseMetadata
        ) -> Void
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
                case .finish(let text, let segments, let language, let duration, _, let metadata):
                    if warningsPending() { resolveWarnings([]) }
                    guard !text.isEmpty else { throw NoTranscriptGeneratedError(responses: [response]) }
                    resolveFinish(text, segments, language, duration, metadata, response)
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
