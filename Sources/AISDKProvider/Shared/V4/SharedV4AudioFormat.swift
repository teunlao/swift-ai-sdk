/**
 Audio format for raw audio exchanged with a model.

 Port of `@ai-sdk/provider/src/shared/v4/shared-v4-audio-format.ts`.
 */
public struct SharedV4AudioFormat: Sendable, Equatable, Codable {
    /// Audio format type, e.g. `audio/pcm`, `audio/pcmu`, or `audio/pcma`.
    public let type: String

    /// Sample rate in Hz. Only applicable for formats that require a rate.
    public let rate: Int?

    public init(type: String, rate: Int? = nil) {
        self.type = type
        self.rate = rate
    }
}
