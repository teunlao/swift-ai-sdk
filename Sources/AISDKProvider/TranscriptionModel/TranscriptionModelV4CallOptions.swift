import Foundation

/**
 Options for transcription calls.

 Port of `@ai-sdk/provider/src/transcription-model/v4/transcription-model-v4-call-options.ts`.
 */
public struct TranscriptionModelV4CallOptions: Sendable {
    public let audio: TranscriptionModelV4Audio
    public let mediaType: String
    public let providerOptions: [String: JSONObject]?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?

    public init(
        audio: TranscriptionModelV4Audio,
        mediaType: String,
        providerOptions: [String: JSONObject]? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil
    ) {
        self.audio = audio
        self.mediaType = mediaType
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}

public enum TranscriptionModelV4Audio: Sendable, Equatable {
    case binary(Data)
    case base64(String)
}
