import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Public exports for the generate-speech module.

 Port of `@ai-sdk/ai/src/generate-speech/index.ts`.
 */

/// Alias matching upstream export name.
public typealias Experimental_SpeechResult = SpeechResult

/// Experimental generate speech entry point (mirrors upstream export name).
public func experimental_generateSpeech(
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
        model: model,
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
