/**
 Options for speech generation calls.

 Port of `@ai-sdk/provider/src/speech-model/v4/speech-model-v4-call-options.ts`.
 */
public struct SpeechModelV4CallOptions: Sendable {
    public let text: String
    public let voice: String?
    public let outputFormat: String?
    public let instructions: String?
    public let speed: Double?
    public let language: String?
    public let providerOptions: [String: JSONObject]?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?

    public init(
        text: String,
        voice: String? = nil,
        outputFormat: String? = nil,
        instructions: String? = nil,
        speed: Double? = nil,
        language: String? = nil,
        providerOptions: [String: JSONObject]? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil
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
