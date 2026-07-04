import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streamed transcription part returned by `streamTranscribe`.

 Port of `@ai-sdk/ai/src/transcribe/stream-transcribe-result.ts`.
 */
public enum TranscriptionStreamPart: Sendable, Equatable {
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
    case raw(rawValue: JSONValue)
    case error(error: JSONValue)
}

/**
 Streaming result returned by `streamTranscribe`.

 The async properties resolve after the provider emits a finish part.
 */
public protocol StreamTranscriptionResult: Sendable {
    var text: String { get async throws }
    var segments: [TranscriptionSegment] { get async throws }
    var language: String? { get async throws }
    var durationInSeconds: Double? { get async throws }
    var warnings: [TranscriptionWarning] { get async throws }
    var responses: [TranscriptionModelResponseMetadata] { get async throws }
    var providerMetadata: [String: JSONObject] { get async throws }
    var fullStream: AsyncIterableStream<TranscriptionStreamPart> { get }
}

public final class DefaultStreamTranscriptionResult: StreamTranscriptionResult, @unchecked Sendable {
    private let textPromise: DelayedPromise<String>
    private let segmentsPromise: DelayedPromise<[TranscriptionSegment]>
    private let languagePromise: DelayedPromise<String?>
    private let durationInSecondsPromise: DelayedPromise<Double?>
    private let warningsPromise: DelayedPromise<[TranscriptionWarning]>
    private let responsesPromise: DelayedPromise<[TranscriptionModelResponseMetadata]>
    private let providerMetadataPromise: DelayedPromise<[String: JSONObject]>

    public let fullStream: AsyncIterableStream<TranscriptionStreamPart>

    init(
        textPromise: DelayedPromise<String>,
        segmentsPromise: DelayedPromise<[TranscriptionSegment]>,
        languagePromise: DelayedPromise<String?>,
        durationInSecondsPromise: DelayedPromise<Double?>,
        warningsPromise: DelayedPromise<[TranscriptionWarning]>,
        responsesPromise: DelayedPromise<[TranscriptionModelResponseMetadata]>,
        providerMetadataPromise: DelayedPromise<[String: JSONObject]>,
        fullStream: AsyncIterableStream<TranscriptionStreamPart>
    ) {
        self.textPromise = textPromise
        self.segmentsPromise = segmentsPromise
        self.languagePromise = languagePromise
        self.durationInSecondsPromise = durationInSecondsPromise
        self.warningsPromise = warningsPromise
        self.responsesPromise = responsesPromise
        self.providerMetadataPromise = providerMetadataPromise
        self.fullStream = fullStream
    }

    public var text: String {
        get async throws { try await textPromise.task.value }
    }

    public var segments: [TranscriptionSegment] {
        get async throws { try await segmentsPromise.task.value }
    }

    public var language: String? {
        get async throws { try await languagePromise.task.value }
    }

    public var durationInSeconds: Double? {
        get async throws { try await durationInSecondsPromise.task.value }
    }

    public var warnings: [TranscriptionWarning] {
        get async throws { try await warningsPromise.task.value }
    }

    public var responses: [TranscriptionModelResponseMetadata] {
        get async throws { try await responsesPromise.task.value }
    }

    public var providerMetadata: [String: JSONObject] {
        get async throws { try await providerMetadataPromise.task.value }
    }
}
