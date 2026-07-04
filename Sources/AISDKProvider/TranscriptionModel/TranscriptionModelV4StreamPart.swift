import Foundation

/**
 A streamed transcription part.

 Port of `@ai-sdk/provider/src/transcription-model/v4/transcription-model-v4-stream-part.ts`.
 */
public enum TranscriptionModelV4StreamPart: Sendable, Equatable {
    case streamStart(warnings: [SharedV4Warning])
    case transcriptDelta(id: String?, delta: String, providerMetadata: SharedV4ProviderMetadata?)
    case transcriptPartial(
        id: String?,
        text: String,
        startSecond: Double?,
        durationInSeconds: Double?,
        channelIndex: Int?,
        providerMetadata: SharedV4ProviderMetadata?
    )
    case transcriptFinal(
        id: String?,
        text: String,
        startSecond: Double?,
        endSecond: Double?,
        channelIndex: Int?,
        providerMetadata: SharedV4ProviderMetadata?
    )
    case responseMetadata(
        timestamp: Date?,
        modelId: String?,
        headers: SharedV4Headers?,
        body: JSONValue?
    )
    case finish(
        text: String,
        segments: [TranscriptionModelV4Result.Segment],
        language: String?,
        durationInSeconds: Double?,
        providerMetadata: [String: JSONObject]?
    )
    case raw(rawValue: JSONValue)
    case error(error: JSONValue)
}
