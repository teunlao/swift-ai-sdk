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
    model: any TranscriptionModelV3,
    audio: TranscriptionAudioInput,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> any TranscriptionResult {
    guard model.specificationVersion == "v3" else {
        throw UnsupportedModelVersionError(
            version: model.specificationVersion,
            provider: model.provider,
            modelId: model.modelId
        )
    }

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let audioData = try await resolveAudioData(audio)

    let result = try await preparedRetries.retry.call {
        try await model.doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: .binary(audioData),
                mediaType: detectMediaType(
                    data: audioData,
                    signatures: audioMediaTypeSignatures
                ) ?? "audio/wav",
                providerOptions: providerOptions,
                abortSignal: abortSignal,
                headers: headersWithUserAgent
            )
        )
    }

    logWarningsForTranscribe(result.warnings.map { Warning.transcriptionModel($0) })

    if result.text.isEmpty {
        let responseMetadata = TranscriptionModelResponseMetadata(
            timestamp: result.response.timestamp,
            modelId: result.response.modelId,
            headers: result.response.headers
        )

        throw NoTranscriptGeneratedError(
            responses: [responseMetadata]
        )
    }

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

private func resolveAudioData(_ audio: TranscriptionAudioInput) async throws -> Data {
    switch audio {
    case .data(let data):
        return data

    case .base64(let base64):
        return try convertBase64ToData(base64)

    case .url(let url):
        return try await download(url: url).data
    }
}
