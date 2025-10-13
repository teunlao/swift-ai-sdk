import Foundation

/**
 Speech model specification version 2.

 Port of `@ai-sdk/provider/src/speech-model/v2/speech-model-v2.ts`.

 The speech model must specify which interface version it implements. This allows evolution
 of the interface while retaining backwards compatibility. Different implementation versions
 can be handled as a discriminated union.
 */
public protocol SpeechModelV2: Sendable {
    /// The specification version this model implements (always "v2")
    var specificationVersion: String { get }

    /// Name of the provider for logging purposes
    var provider: String { get }

    /// Provider-specific model ID for logging purposes
    var modelId: String { get }

    /// Generates speech audio from text
    func doGenerate(options: SpeechModelV2CallOptions) async throws -> SpeechModelV2Result
}

extension SpeechModelV2 {
    public var specificationVersion: String { "v2" }
}

/// Result from a speech generation call
public struct SpeechModelV2Result: Sendable {
    /// Generated audio.
    /// The audio should be returned without any unnecessary conversion.
    /// If the API returns base64 encoded strings, the audio should be returned as base64 strings.
    /// If the API returns binary data, the audio should be returned as binary data.
    public let audio: SpeechModelV2Audio

    /// Warnings for the call, e.g., unsupported settings
    public let warnings: [SpeechModelV2CallWarning]

    /// Optional request information for telemetry and debugging purposes
    public let request: RequestInfo?

    /// Response information for telemetry and debugging purposes
    public let response: ResponseInfo

    /// Additional provider-specific metadata.
    /// They are passed through from the provider to the AI SDK and enable provider-specific
    /// results that can be fully encapsulated in the provider.
    public let providerMetadata: [String: [String: JSONValue]]?

    public init(
        audio: SpeechModelV2Audio,
        warnings: [SpeechModelV2CallWarning] = [],
        request: RequestInfo? = nil,
        response: ResponseInfo,
        providerMetadata: [String: [String: JSONValue]]? = nil
    ) {
        self.audio = audio
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    /// Request information for telemetry and debugging
    public struct RequestInfo: @unchecked Sendable {
        /// Request body (available only for providers that use HTTP requests)
        /// Marked @unchecked Sendable to match TypeScript's unknown type.
        public let body: Any?

        public init(body: Any? = nil) {
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

/// Audio output from speech generation
public enum SpeechModelV2Audio: Sendable, Equatable {
    /// Base64-encoded audio string
    case base64(String)

    /// Binary audio data
    case binary(Data)
}
