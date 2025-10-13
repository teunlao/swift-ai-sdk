import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Generates speech audio using a speech model.

 Port of `@ai-sdk/ai/src/generate-speech/generate-speech.ts`.
 */

/// Internal hook to allow tests to observe warning logging behavior.
nonisolated(unsafe) var logWarningsForGenerateSpeech: ([Warning]) -> Void = logWarnings

private func makeHeadersWithUserAgent(_ headers: [String: String]?) -> [String: String] {
    let normalized: [String: String?]
    if let headers {
        normalized = headers.mapValues { Optional($0) }
    } else {
        normalized = [:]
    }

    return withUserAgentSuffix(
        normalized,
        "ai/\(VERSION)"
    )
}

private func makeGeneratedAudioFile(from audio: SpeechModelV3Audio) -> GeneratedAudioFile {
    switch audio {
    case .binary(let data):
        let mediaType = detectMediaType(
            data: data,
            signatures: audioMediaTypeSignatures
        ) ?? "audio/mp3"
        return DefaultGeneratedAudioFile(data: data, mediaType: mediaType)

    case .base64(let base64):
        let mediaType = detectMediaType(
            data: base64,
            signatures: audioMediaTypeSignatures
        ) ?? "audio/mp3"
        return DefaultGeneratedAudioFile(base64: base64, mediaType: mediaType)
    }
}

private func isAudioEmpty(_ audio: SpeechModelV3Audio) -> Bool {
    switch audio {
    case .binary(let data):
        return data.isEmpty
    case .base64(let base64):
        return base64.isEmpty
    }
}

/**
 Generates speech audio using a speech model.

 - Parameters:
   - model: The speech model to use.
   - text: The text to convert to speech.
   - voice: The voice to use for speech generation.
   - outputFormat: Desired output format (e.g., "mp3", "wav").
   - instructions: Additional instructions for speech generation.
   - speed: Speech generation speed.
   - language: Language for speech generation (ISO 639-1 code or "auto").
   - providerOptions: Provider-specific options (default: empty dictionary).
   - maxRetries: Maximum number of retries (default: 2).
   - abortSignal: Optional abort signal for cancellation.
   - headers: Additional HTTP headers (HTTP-based providers only).

 - Returns: A `SpeechResult` containing the generated audio and metadata.
 - Throws: `UnsupportedModelVersionError`, `NoSpeechGeneratedError`, or retry-related errors.
 */
public func generateSpeech(
    model: any SpeechModelV3,
    text: String,
    voice: String? = nil,
    outputFormat: String? = nil,
    instructions: String? = nil,
    speed: Double? = nil,
    language: String? = nil,
    providerOptions: ProviderOptions = [:],
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> any SpeechResult {
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

    let headersWithUserAgent = makeHeadersWithUserAgent(headers)

    let result = try await preparedRetries.retry.call {
        try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: text,
                voice: voice,
                outputFormat: outputFormat,
                instructions: instructions,
                speed: speed,
                language: language,
                providerOptions: providerOptions,
                abortSignal: abortSignal,
                headers: headersWithUserAgent
            )
        )
    }

    if isAudioEmpty(result.audio) {
        let responseMetadata = SpeechModelResponseMetadata(
            timestamp: result.response.timestamp,
            modelId: result.response.modelId,
            headers: result.response.headers,
            body: result.response.body
        )

        throw NoSpeechGeneratedError(
            responses: [responseMetadata]
        )
    }

    let audioFile = makeGeneratedAudioFile(from: result.audio)

    let warnings = result.warnings
    let warningEntries = warnings.map { Warning.speechModel($0) }
    logWarningsForGenerateSpeech(warningEntries)

    let responseMetadata = SpeechModelResponseMetadata(
        timestamp: result.response.timestamp,
        modelId: result.response.modelId,
        headers: result.response.headers,
        body: result.response.body
    )

    return DefaultSpeechResult(
        audio: audioFile,
        warnings: warnings,
        responses: [responseMetadata],
        providerMetadata: result.providerMetadata ?? [:]
    )
}
