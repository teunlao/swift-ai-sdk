import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Public exports for the transcribe module.

 Port of `@ai-sdk/ai/src/transcribe/index.ts`.
 */

/// Alias matching upstream export name.
public typealias Experimental_StreamTranscriptionResult = StreamTranscriptionResult
public typealias Experimental_TranscriptionResult = TranscriptionResult

@available(*, deprecated, renamed: "transcribe")
public func experimental_transcribe(
    model: TranscriptionModel,
    audio: TranscriptionAudioInput,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalDownload download: DownloadFileFunction? = nil
) async throws -> any TranscriptionResult {
    logWarnings([.transcriptionModel(.deprecated(setting: "experimental_transcribe", message: "Use transcribe instead."))])
    return try await transcribe(
        model: model, audio: audio, providerOptions: providerOptions,
        maxRetries: maxRetries, abortSignal: abortSignal, headers: headers,
        experimentalDownload: download
    )
}

/// Experimental streaming transcription entry point (mirrors upstream export name).
public func experimental_streamTranscribe(
    model: TranscriptionModel,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: model,
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks
    )
}

/// Experimental streaming transcription entry point (mirrors upstream export name).
public func experimental_streamTranscribe(
    model: any TranscriptionModelV4,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: model,
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks
    )
}

/// Experimental streaming transcription entry point (mirrors upstream export name).
public func experimental_streamTranscribe(
    model: any TranscriptionModelV3,
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: ProviderOptions = [:],
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    includeRawChunks: Bool? = nil
) throws -> any StreamTranscriptionResult {
    try streamTranscribe(
        model: model,
        audio: audio,
        inputAudioFormat: inputAudioFormat,
        providerOptions: providerOptions,
        abortSignal: abortSignal,
        headers: headers,
        includeRawChunks: includeRawChunks
    )
}
