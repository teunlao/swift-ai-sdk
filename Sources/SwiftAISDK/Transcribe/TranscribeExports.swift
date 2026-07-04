import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Public exports for the transcribe module.

 Port of `@ai-sdk/ai/src/transcribe/index.ts`.
 */

/// Alias matching upstream export name.
public typealias Experimental_StreamTranscriptionResult = StreamTranscriptionResult

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

/// Experimental streaming transcription entry point (mirrors upstream export name).
public func experimental_streamTranscribe(
    model: any TranscriptionModelV2,
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
