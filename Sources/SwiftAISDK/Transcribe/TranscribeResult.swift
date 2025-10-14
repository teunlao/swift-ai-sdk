import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of a `transcribe` call. It contains the transcript and additional information.

 Port of `@ai-sdk/ai/src/transcribe/transcribe-result.ts`.
 */
public protocol TranscriptionResult: Sendable {
    /// The complete transcribed text from the audio.
    var text: String { get }

    /// Array of transcript segments with timing information.
    var segments: [TranscriptionSegment] { get }

    /// The detected language of the audio content (ISO-639-1), if available.
    var language: String? { get }

    /// The total duration of the audio file in seconds, if available.
    var durationInSeconds: Double? { get }

    /// Warnings for the call, e.g. unsupported settings.
    var warnings: [TranscriptionWarning] { get }

    /// Response metadata from the provider. There may be multiple responses if we made multiple calls.
    var responses: [TranscriptionModelResponseMetadata] { get }

    /// Provider metadata returned by the provider.
    var providerMetadata: [String: [String: JSONValue]] { get }
}

/// Transcript segment with timing information.
public struct TranscriptionSegment: Sendable, Equatable {
    /// The text content of this segment.
    public let text: String

    /// The start time of this segment in seconds.
    public let startSecond: Double

    /// The end time of this segment in seconds.
    public let endSecond: Double

    public init(text: String, startSecond: Double, endSecond: Double) {
        self.text = text
        self.startSecond = startSecond
        self.endSecond = endSecond
    }
}

/// Default implementation of `TranscriptionResult`.
public final class DefaultTranscriptionResult: TranscriptionResult, @unchecked Sendable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let language: String?
    public let durationInSeconds: Double?
    public let warnings: [TranscriptionWarning]
    public let responses: [TranscriptionModelResponseMetadata]
    public let providerMetadata: [String: [String: JSONValue]]

    public init(
        text: String,
        segments: [TranscriptionSegment],
        language: String?,
        durationInSeconds: Double?,
        warnings: [TranscriptionWarning],
        responses: [TranscriptionModelResponseMetadata],
        providerMetadata: [String: [String: JSONValue]]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.responses = responses
        self.providerMetadata = providerMetadata ?? [:]
    }
}
