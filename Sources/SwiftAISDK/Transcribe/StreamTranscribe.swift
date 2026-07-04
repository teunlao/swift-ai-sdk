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
    let resolvedModel = try resolveTranscriptionModelV4(model)
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

public func streamTranscribe(
    model: any TranscriptionModelV2,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: .v2(model),
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

    let state = StreamTranscribeState(startedAt: Date(), modelId: model.modelId)

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

    let stream = AsyncThrowingStream<TranscriptionStreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                let result = try await model.doStream(
                    options: TranscriptionModelV4StreamOptions(
                        audio: audio,
                        inputAudioFormat: inputAudioFormat,
                        providerOptions: providerOptions,
                        abortSignal: abortSignal,
                        headers: headersWithUserAgent,
                        includeRawChunks: includeRawChunks
                    )
                )

                await state.updateResponse(result.response)

                for try await part in result.stream {
                    switch part {
                    case .streamStart(let warnings):
                        if warningsPromise.isPending() {
                            resolveWarnings(warnings)
                        }

                    case let .responseMetadata(timestamp, modelId, headers, _):
                        await state.updateResponse(
                            timestamp: timestamp,
                            modelId: modelId,
                            headers: headers
                        )

                    case let .transcriptDelta(id, delta, providerMetadata):
                        continuation.yield(.transcriptDelta(id: id, delta: delta, providerMetadata: providerMetadata))

                    case let .transcriptPartial(id, text, startSecond, durationInSeconds, channelIndex, providerMetadata):
                        continuation.yield(.transcriptPartial(
                            id: id,
                            text: text,
                            startSecond: startSecond,
                            durationInSeconds: durationInSeconds,
                            channelIndex: channelIndex,
                            providerMetadata: providerMetadata
                        ))

                    case let .transcriptFinal(id, text, startSecond, endSecond, channelIndex, providerMetadata):
                        continuation.yield(.transcriptFinal(
                            id: id,
                            text: text,
                            startSecond: startSecond,
                            endSecond: endSecond,
                            channelIndex: channelIndex,
                            providerMetadata: providerMetadata
                        ))

                    case let .raw(rawValue):
                        continuation.yield(.raw(rawValue: rawValue))

                    case let .error(error):
                        continuation.yield(.error(error: error))

                    case let .finish(text, segments, language, durationInSeconds, providerMetadata):
                        if warningsPromise.isPending() {
                            resolveWarnings([])
                        }

                        let response = await state.currentResponseMetadata()
                        guard !text.isEmpty else {
                            throw NoTranscriptGeneratedError(responses: [response])
                        }

                        textPromise.resolve(text)
                        segmentsPromise.resolve(segments.map {
                            TranscriptionSegment(
                                text: $0.text,
                                startSecond: $0.startSecond,
                                endSecond: $0.endSecond
                            )
                        })
                        languagePromise.resolve(language)
                        durationInSecondsPromise.resolve(durationInSeconds)
                        responsesPromise.resolve([response])
                        providerMetadataPromise.resolve(providerMetadata ?? [:])
                    }
                }

                if textPromise.isPending() {
                    throw NoTranscriptGeneratedError(responses: [await state.currentResponseMetadata()])
                }

                continuation.finish()
            } catch {
                rejectPending(error)
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable termination in
            guard case .cancelled = termination else {
                return
            }
            task.cancel()
            rejectPending(CancellationError())
        }
    }

    return DefaultStreamTranscriptionResult(
        textPromise: textPromise,
        segmentsPromise: segmentsPromise,
        languagePromise: languagePromise,
        durationInSecondsPromise: durationInSecondsPromise,
        warningsPromise: warningsPromise,
        responsesPromise: responsesPromise,
        providerMetadataPromise: providerMetadataPromise,
        fullStream: createAsyncIterableStream(source: stream)
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

private actor StreamTranscribeState {
    private let startedAt: Date
    private let defaultModelId: String
    private var response: TranscriptionModelResponseMetadata?

    init(startedAt: Date, modelId: String) {
        self.startedAt = startedAt
        self.defaultModelId = modelId
    }

    func updateResponse(_ response: TranscriptionModelV4StreamResult.ResponseInfo?) {
        self.response = TranscriptionModelResponseMetadata(
            timestamp: response?.timestamp ?? startedAt,
            modelId: response?.modelId ?? defaultModelId,
            headers: response?.headers
        )
    }

    func updateResponse(timestamp: Date?, modelId: String?, headers: SharedV4Headers?) {
        let current = currentResponseMetadata()
        response = TranscriptionModelResponseMetadata(
            timestamp: timestamp ?? current.timestamp,
            modelId: modelId ?? current.modelId,
            headers: headers ?? current.headers
        )
    }

    func currentResponseMetadata() -> TranscriptionModelResponseMetadata {
        response ?? TranscriptionModelResponseMetadata(
            timestamp: startedAt,
            modelId: defaultModelId
        )
    }
}
