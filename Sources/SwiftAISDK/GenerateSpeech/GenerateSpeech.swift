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

private func makeGeneratedAudioFile(
    from audio: SpeechModelV4Audio,
    headers: SharedV4Headers?,
    outputFormat: String?
) throws -> GeneratedAudioFile {
    let headerMediaType = headers?.first { $0.key.lowercased() == "content-type" }?.value
        .split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    let normalizedFormat = outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let formatMediaType: String?
    switch normalizedFormat {
    case "pcm", "audio/pcm": formatMediaType = "audio/pcm"
    case "audio/l16": formatMediaType = "audio/l16"
    case "mulaw", "audio/mulaw": formatMediaType = "audio/mulaw"
    case "alaw", "audio/alaw": formatMediaType = "audio/alaw"
    default: formatMediaType = nil
    }
    let fallback = (headerMediaType?.hasPrefix("audio/") == true ? headerMediaType : nil)
        ?? formatMediaType ?? "audio/mp3"
    switch audio {
    case .binary(let data):
        let mediaType = detectMediaType(
            data: data,
            topLevelType: "audio"
        ) ?? fallback
        return try DefaultGeneratedAudioFile(data: data, mediaType: mediaType)

    case .base64(let base64):
        let mediaType = detectMediaType(
            data: base64,
            topLevelType: "audio"
        ) ?? fallback
        return try DefaultGeneratedAudioFile(base64: base64, mediaType: mediaType)
    }
}

private func isAudioEmpty(_ audio: SpeechModelV4Audio) -> Bool {
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
    model: SpeechModel,
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
    guard let model = try resolveSpeechModelV4(model) else {
        throw ModelResolutionFailure(message: "Model could not be resolved")
    }

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let headersWithUserAgent = makeHeadersWithUserAgent(headers)

    let result = try await preparedRetries.retry.call {
        try await model.doGenerate(
            options: SpeechModelV4CallOptions(
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

    let warnings = result.warnings
    let warningEntries = warnings.map { Warning.speechModel($0) }
    logWarningsForGenerateSpeech(warningEntries)

    let audioFile = try makeGeneratedAudioFile(from: result.audio, headers: result.response.headers, outputFormat: outputFormat)

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

public func generateSpeech(
    model: any SpeechModelV4,
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
    try await generateSpeech(
        model: .v4(model),
        text: text,
        voice: voice,
        outputFormat: outputFormat,
        instructions: instructions,
        speed: speed,
        language: language,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

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
    try await generateSpeech(
        model: .v3(model),
        text: text,
        voice: voice,
        outputFormat: outputFormat,
        instructions: instructions,
        speed: speed,
        language: language,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}
