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
    var fullStream: AsyncIterableStream<TranscriptionStreamPart> { get throws }
}

public enum StreamTranscriptionAccessError: Error, LocalizedError, Sendable, Equatable {
    case fullStreamAlreadyAccessed
    case resultAlreadyAccessed

    public var errorDescription: String? {
        switch self {
        case .fullStreamAlreadyAccessed: return "fullStream can only be accessed once."
        case .resultAlreadyAccessed: return "fullStream cannot be accessed after a result promise."
        }
    }
}

public final class DefaultStreamTranscriptionResult: StreamTranscriptionResult, @unchecked Sendable {
    private let textPromise: DelayedPromise<String>
    private let segmentsPromise: DelayedPromise<[TranscriptionSegment]>
    private let languagePromise: DelayedPromise<String?>
    private let durationInSecondsPromise: DelayedPromise<Double?>
    private let warningsPromise: DelayedPromise<[TranscriptionWarning]>
    private let responsesPromise: DelayedPromise<[TranscriptionModelResponseMetadata]>
    private let providerMetadataPromise: DelayedPromise<[String: JSONObject]>

    private enum Owner { case unclaimed, fullStream, results }
    private let lock = NSLock()
    private var owner: Owner = .unclaimed
    private let stream: AsyncIterableStream<TranscriptionStreamPart>
    private var drainTask: Task<Void, Never>?

    public var fullStream: AsyncIterableStream<TranscriptionStreamPart> {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            switch owner {
            case .unclaimed: owner = .fullStream; return stream
            case .fullStream: throw StreamTranscriptionAccessError.fullStreamAlreadyAccessed
            case .results: throw StreamTranscriptionAccessError.resultAlreadyAccessed
            }
        }
    }

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
        self.stream = fullStream
    }

    public var text: String {
        get async throws { consumeStream(); return try await textPromise.task.value }
    }

    public var segments: [TranscriptionSegment] {
        get async throws { consumeStream(); return try await segmentsPromise.task.value }
    }

    public var language: String? {
        get async throws { consumeStream(); return try await languagePromise.task.value }
    }

    public var durationInSeconds: Double? {
        get async throws { consumeStream(); return try await durationInSecondsPromise.task.value }
    }

    public var warnings: [TranscriptionWarning] {
        get async throws { consumeStream(); return try await warningsPromise.task.value }
    }

    public var responses: [TranscriptionModelResponseMetadata] {
        get async throws { consumeStream(); return try await responsesPromise.task.value }
    }

    public var providerMetadata: [String: JSONObject] {
        get async throws { consumeStream(); return try await providerMetadataPromise.task.value }
    }

    private func consumeStream() {
        lock.lock()
        defer { lock.unlock() }
        guard owner == .unclaimed else { return }
        owner = .results
        let stream = stream
        drainTask = Task {
            do { for try await _ in stream {} }
            catch { /* Stream processing owns rejection of all pending result promises. */ }
        }
    }

    deinit { drainTask?.cancel() }
}
