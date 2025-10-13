import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of a `generateSpeech` call. It contains the audio data and additional information.

 Port of `@ai-sdk/ai/src/generate-speech/generate-speech-result.ts`.
 */
public protocol SpeechResult: Sendable {
    /// The generated audio.
    var audio: GeneratedAudioFile { get }

    /// Warnings for the call, e.g. unsupported settings.
    var warnings: [SpeechWarning] { get }

    /// Response metadata from the provider. There may be multiple responses if we made multiple calls.
    var responses: [SpeechModelResponseMetadata] { get }

    /// Provider metadata returned by the provider.
    var providerMetadata: [String: [String: JSONValue]] { get }
}

/// Default implementation of `SpeechResult`.
public final class DefaultSpeechResult: SpeechResult, @unchecked Sendable {
    public let audio: GeneratedAudioFile
    public let warnings: [SpeechWarning]
    public let responses: [SpeechModelResponseMetadata]
    public let providerMetadata: [String: [String: JSONValue]]

    public init(
        audio: GeneratedAudioFile,
        warnings: [SpeechWarning],
        responses: [SpeechModelResponseMetadata],
        providerMetadata: [String: [String: JSONValue]]? = nil
    ) {
        self.audio = audio
        self.warnings = warnings
        self.responses = responses
        self.providerMetadata = providerMetadata ?? [:]
    }
}
