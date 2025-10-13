/**
 Options for speech generation calls.

 Port of `@ai-sdk/provider/src/speech-model/v2/speech-model-v2-call-options.ts`.
 */
public struct SpeechModelV2CallOptions: Sendable {
    /// Text to convert to speech
    public let text: String

    /// The voice to use for speech synthesis.
    /// This is provider-specific and may be a voice ID, name, or other identifier.
    public let voice: String?

    /// The desired output format for the audio (e.g., "mp3", "wav")
    public let outputFormat: String?

    /// Instructions for the speech generation (e.g., "Speak in a slow and steady tone")
    public let instructions: String?

    /// The speed of the speech generation
    public let speed: Double?

    /// The language for speech generation.
    /// This should be an ISO 639-1 language code (e.g., "en", "es", "fr")
    /// or "auto" for automatic language detection. Provider support varies.
    public let language: String?

    /// Additional provider-specific options that are passed through to the provider as body parameters.
    ///
    /// The outer dictionary is keyed by the provider name, and the inner dictionary
    /// is keyed by the provider-specific metadata key.
    /// ```swift
    /// ["openai": [:]]
    /// ```
    public let providerOptions: [String: [String: JSONValue]]?

    /// Closure to check if the operation should be aborted
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional HTTP headers to be sent with the request.
    /// Only applicable for HTTP-based providers.
    public let headers: [String: String]?

    public init(
        text: String,
        voice: String? = nil,
        outputFormat: String? = nil,
        instructions: String? = nil,
        speed: Double? = nil,
        language: String? = nil,
        providerOptions: [String: [String: JSONValue]]? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil
    ) {
        self.text = text
        self.voice = voice
        self.outputFormat = outputFormat
        self.instructions = instructions
        self.speed = speed
        self.language = language
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}
