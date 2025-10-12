import Foundation

/**
 Options for transcription calls.

 Port of `@ai-sdk/provider/src/transcription-model/v2/transcription-model-v2-call-options.ts`.
 */
public struct TranscriptionModelV2CallOptions: Sendable {
    /// Audio data to transcribe.
    /// Accepts `Data` (binary) or `String` (base64 encoded audio file).
    public let audio: TranscriptionModelV2Audio

    /// The IANA media type of the audio data.
    /// See: https://www.iana.org/assignments/media-types/media-types.xhtml
    public let mediaType: String

    /// Additional provider-specific options that are passed through to the provider as body parameters.
    ///
    /// The outer dictionary is keyed by the provider name, and the inner dictionary
    /// is keyed by the provider-specific metadata key.
    /// ```swift
    /// ["openai": ["timestampGranularities": ["word"]]]
    /// ```
    public let providerOptions: [String: [String: JSONValue]]?

    /// Closure to check if the operation should be aborted
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional HTTP headers to be sent with the request.
    /// Only applicable for HTTP-based providers.
    public let headers: [String: String]?

    public init(
        audio: TranscriptionModelV2Audio,
        mediaType: String,
        providerOptions: [String: [String: JSONValue]]? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil
    ) {
        self.audio = audio
        self.mediaType = mediaType
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}

/// Audio input for transcription
public enum TranscriptionModelV2Audio: Sendable, Equatable {
    /// Binary audio data
    case binary(Data)

    /// Base64-encoded audio string
    case base64(String)
}
