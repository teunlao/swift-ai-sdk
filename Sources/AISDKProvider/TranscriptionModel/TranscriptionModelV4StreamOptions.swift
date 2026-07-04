import Foundation

/**
 Options for streaming transcription calls.

 Port of `@ai-sdk/provider/src/transcription-model/v4/transcription-model-v4-stream-options.ts`.
 */
public struct TranscriptionModelV4StreamOptions: Sendable {
    public let audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>
    public let inputAudioFormat: InputAudioFormat
    public let providerOptions: SharedV4ProviderOptions?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?
    public let includeRawChunks: Bool?

    public init(
        audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
        inputAudioFormat: InputAudioFormat,
        providerOptions: SharedV4ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil,
        includeRawChunks: Bool? = nil
    ) {
        self.audio = audio
        self.inputAudioFormat = inputAudioFormat
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
        self.includeRawChunks = includeRawChunks
    }

    public struct InputAudioFormat: Sendable, Equatable {
        public let type: String
        public let rate: Int?

        public init(type: String, rate: Int? = nil) {
            self.type = type
            self.rate = rate
        }
    }
}

public enum TranscriptionModelV4StreamAudio: Sendable, Equatable {
    case binary(Data)
    case base64(String)
}
