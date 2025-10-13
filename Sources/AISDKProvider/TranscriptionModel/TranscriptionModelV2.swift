import Foundation

/**
 Transcription model specification version 2.

 Port of `@ai-sdk/provider/src/transcription-model/v2/transcription-model-v2.ts`.

 The transcription model must specify which interface version it implements. This allows evolution
 of the interface while retaining backwards compatibility. Different implementation versions
 can be handled as a discriminated union.
 */
public protocol TranscriptionModelV2: Sendable {
    /// The specification version this model implements (always "v2")
    var specificationVersion: String { get }

    /// Name of the provider for logging purposes
    var provider: String { get }

    /// Provider-specific model ID for logging purposes
    var modelId: String { get }

    /// Generates a transcript from audio
    func doGenerate(options: TranscriptionModelV2CallOptions) async throws -> TranscriptionModelV2Result
}

extension TranscriptionModelV2 {
    public var specificationVersion: String { "v2" }
}

/// Result from a transcription call
public struct TranscriptionModelV2Result: Sendable {
    /// The complete transcribed text from the audio
    public let text: String

    /// Array of transcript segments with timing information.
    /// Each segment represents a portion of the transcribed text with start and end times.
    public let segments: [Segment]

    /// The detected language of the audio content, as an ISO-639-1 code (e.g., "en" for English).
    /// May be nil if the language couldn't be detected.
    public let language: String?

    /// The total duration of the audio file in seconds.
    /// May be nil if the duration couldn't be determined.
    public let durationInSeconds: Double?

    /// Warnings for the call, e.g., unsupported settings
    public let warnings: [TranscriptionModelV2CallWarning]

    /// Optional request information for telemetry and debugging purposes
    public let request: RequestInfo?

    /// Response information for telemetry and debugging purposes
    public let response: ResponseInfo

    /// Additional provider-specific metadata.
    /// They are passed through from the provider to the AI SDK and enable provider-specific
    /// results that can be fully encapsulated in the provider.
    public let providerMetadata: [String: [String: JSONValue]]?

    public init(
        text: String,
        segments: [Segment],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [TranscriptionModelV2CallWarning] = [],
        request: RequestInfo? = nil,
        response: ResponseInfo,
        providerMetadata: [String: [String: JSONValue]]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    /// Transcript segment with timing information
    public struct Segment: Sendable {
        /// The text content of this segment
        public let text: String

        /// The start time of this segment in seconds
        public let startSecond: Double

        /// The end time of this segment in seconds
        public let endSecond: Double

        public init(text: String, startSecond: Double, endSecond: Double) {
            self.text = text
            self.startSecond = startSecond
            self.endSecond = endSecond
        }
    }

    /// Request information for telemetry and debugging
    public struct RequestInfo: Sendable {
        /// Raw request HTTP body that was sent to the provider API as a string (JSON should be stringified).
        /// Non-HTTP(s) providers should not set this.
        public let body: String?

        public init(body: String? = nil) {
            self.body = body
        }
    }

    /// Response information for telemetry and debugging
    public struct ResponseInfo: @unchecked Sendable {
        /// Timestamp for the start of the generated response
        public let timestamp: Date

        /// The ID of the response model that was used to generate the response
        public let modelId: String

        /// Response headers
        public let headers: SharedV2Headers?

        /// Response body
        /// Marked @unchecked Sendable to match TypeScript's unknown type.
        public let body: Any?

        public init(
            timestamp: Date,
            modelId: String,
            headers: SharedV2Headers? = nil,
            body: Any? = nil
        ) {
            self.timestamp = timestamp
            self.modelId = modelId
            self.headers = headers
            self.body = body
        }
    }
}
