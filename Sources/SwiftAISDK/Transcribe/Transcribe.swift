import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Internal hook to allow tests to observe warning logging behavior.
nonisolated(unsafe) var logWarningsForTranscribe: ([Warning]) -> Void = logWarnings

/**
 Generates transcripts using a transcription model.

 Port of `@ai-sdk/ai/src/transcribe/transcribe.ts`.
 */
public func transcribe(
    model: TranscriptionModel,
    audio: TranscriptionAudioInput,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalDownload download: DownloadFileFunction? = nil,
    telemetry: TelemetryOptions? = nil
) async throws -> any TranscriptionResult {
    guard let resolvedModel = try resolveTranscriptionModelV4(model) else {
        throw ModelResolutionFailure(message: "Model could not be resolved")
    }

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let callId = try createIDGenerator(prefix: "call", size: 24)()
    let dispatcher = TelemetryDispatcher(telemetry: telemetry)

    func startEvent(byteLength: Int?, mediaType: String?) -> TranscriptionStartEvent {
        TranscriptionStartEvent(
            callId: callId, operationId: "ai.transcribe",
            provider: resolvedModel.provider, modelId: resolvedModel.modelId,
            audio: .init(byteLength: byteLength, mediaType: mediaType),
            inputAudioFormat: nil, maxRetries: preparedRetries.maxRetries,
            headers: headers, providerOptions: providerOptions
        )
    }

    let audioData: (data: Data, mediaType: String?)
    do {
        audioData = try await resolveAudioData(
            audio,
            download: download ?? createDownload(),
            abortSignal: abortSignal
        )
    } catch {
        await dispatcher.onStart(.transcribe(startEvent(byteLength: nil, mediaType: nil)))
        await dispatcher.onError(callId: callId, error: error)
        throw error
    }

    let mediaType = audioData.mediaType
        ?? detectMediaType(data: audioData.data, topLevelType: "audio")
        ?? "audio/wav"
    await dispatcher.onStart(.transcribe(startEvent(byteLength: audioData.data.count, mediaType: mediaType)))

    let result: TranscriptionModelV4Result
    do {
        result = try await preparedRetries.retry.call {
            try await resolvedModel.doGenerate(
                options: TranscriptionModelV4CallOptions(
                    audio: .binary(audioData.data),
                    mediaType: mediaType,
                    providerOptions: providerOptions,
                    abortSignal: abortSignal,
                    headers: headersWithUserAgent
                )
            )
        }
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw error
    }

    logWarningsForTranscribe(result.warnings.map { Warning.transcriptionModel($0) })

    let segments = result.segments.map { segment in
        TranscriptionSegment(
            text: segment.text,
            startSecond: segment.startSecond,
            endSecond: segment.endSecond
        )
    }

    let responseMetadata = TranscriptionModelResponseMetadata(
        timestamp: result.response.timestamp,
        modelId: result.response.modelId,
        headers: result.response.headers
    )

    await dispatcher.onEnd(.transcribe(TranscriptionEndEvent(
        callId: callId, operationId: "ai.transcribe",
        provider: resolvedModel.provider, modelId: resolvedModel.modelId,
        audio: .init(byteLength: audioData.data.count, mediaType: mediaType),
        text: result.text, segments: segments, language: result.language,
        durationInSeconds: result.durationInSeconds, usage: result.usage,
        warnings: result.warnings, providerMetadata: result.providerMetadata,
        response: responseMetadata
    )))

    return DefaultTranscriptionResult(
        text: result.text,
        segments: segments,
        language: result.language,
        durationInSeconds: result.durationInSeconds,
        warnings: result.warnings,
        responses: [responseMetadata],
        providerMetadata: result.providerMetadata ?? [:]
    )
}

public func transcribe(
    model: any TranscriptionModelV4,
    audio: TranscriptionAudioInput,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalDownload download: DownloadFileFunction? = nil,
    telemetry: TelemetryOptions? = nil
) async throws -> any TranscriptionResult {
    try await transcribe(
        model: .v4(model),
        audio: audio,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalDownload: download,
        telemetry: telemetry
    )
}

public func transcribe(
    model: any TranscriptionModelV3,
    audio: TranscriptionAudioInput,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalDownload download: DownloadFileFunction? = nil,
    telemetry: TelemetryOptions? = nil
) async throws -> any TranscriptionResult {
    try await transcribe(
        model: .v3(model),
        audio: audio,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalDownload: download,
        telemetry: telemetry
    )
}

/**
 Audio input for transcription.

 Mirrors TypeScript union `DataContent | URL`.
 */
public enum TranscriptionAudioInput: Sendable, Equatable {
    /// Binary audio data (equivalent to Uint8Array / ArrayBuffer / Buffer).
    case data(Data)

    /// Base64-encoded audio string.
    case base64(String)

    /// Remote audio fetched from a URL.
    case url(URL)

    /// Convenience case for provider-utils `DataContent`.
    public static func dataContent(_ content: DataContent) -> TranscriptionAudioInput {
        switch content {
        case .data(let data):
            return .data(data)
        case .string(let value):
            return .base64(value)
        }
    }
}

private func resolveAudioData(
    _ audio: TranscriptionAudioInput,
    download: DownloadFileFunction,
    abortSignal: (@Sendable () -> Bool)?
) async throws -> (data: Data, mediaType: String?) {
    switch audio {
    case .data(let data):
        return (data, nil)

    case .base64(let base64):
        return (try convertBase64ToData(base64), nil)

    case .url(let url):
        let result = try await download(
            DownloadFileRequest(
                url: url,
                abortSignal: abortSignal
            )
        )
        return (result.data, result.mediaType)
    }
}
