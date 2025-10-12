import Foundation

/**
 Specification for a language model that implements the language model interface version 2.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3 = {
   readonly specificationVersion: 'v2';
   readonly provider: string;
   readonly modelId: string;
   supportedUrls: PromiseLike<Record<string, RegExp[]>> | Record<string, RegExp[]>;
   doGenerate(options: LanguageModelV3CallOptions): PromiseLike<{...}>;
   doStream(options: LanguageModelV3CallOptions): PromiseLike<{...}>;
 };
 ```
 */
public protocol LanguageModelV3: Sendable {
    /// The language model must specify which language model interface version it implements.
    var specificationVersion: String { get }

    /// Name of the provider for logging purposes.
    var provider: String { get }

    /// Provider-specific model ID for logging purposes.
    var modelId: String { get }

    /// Supported URL patterns by media type for the provider.
    /// The keys are media type patterns or full media types (e.g. `*/*` for everything, `audio/*`, `video/*`, or `application/pdf`).
    /// and the values are arrays of regular expressions that match the URL paths.
    /// The matching should be against lower-case URLs.
    /// Matched URLs are supported natively by the model and are not downloaded.
    var supportedUrls: [String: [NSRegularExpression]] { get async throws }

    /// Generates a language model output (non-streaming).
    /// Naming: "do" prefix to prevent accidental direct usage of the method by the user.
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult

    /// Generates a language model output (streaming).
    /// Naming: "do" prefix to prevent accidental direct usage of the method by the user.
    /// @return A stream of higher-level language model output parts.
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult
}

extension LanguageModelV3 {
    public var specificationVersion: String { "v2" }

    /// Default implementation returns empty dictionary (no native URL support)
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }
}

/// Result of doGenerate call
public struct LanguageModelV3GenerateResult: Sendable {
    /// Ordered content that the model has generated.
    public let content: [LanguageModelV3Content]

    /// Finish reason.
    public let finishReason: LanguageModelV3FinishReason

    /// Usage information.
    public let usage: LanguageModelV3Usage

    /// Additional provider-specific metadata.
    public let providerMetadata: SharedV3ProviderMetadata?

    /// Optional request information for telemetry and debugging purposes.
    public let request: LanguageModelV3RequestInfo?

    /// Optional response information for telemetry and debugging purposes.
    public let response: LanguageModelV3ResponseInfo?

    /// Warnings for the call, e.g. unsupported settings.
    public let warnings: [LanguageModelV3CallWarning]

    public init(
        content: [LanguageModelV3Content],
        finishReason: LanguageModelV3FinishReason,
        usage: LanguageModelV3Usage,
        providerMetadata: SharedV3ProviderMetadata? = nil,
        request: LanguageModelV3RequestInfo? = nil,
        response: LanguageModelV3ResponseInfo? = nil,
        warnings: [LanguageModelV3CallWarning] = []
    ) {
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.request = request
        self.response = response
        self.warnings = warnings
    }
}

/// Result of doStream call
public struct LanguageModelV3StreamResult: Sendable {
    /// Stream of higher-level language model output parts.
    public let stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>

    /// Optional request information for telemetry and debugging purposes.
    public let request: LanguageModelV3RequestInfo?

    /// Optional response data.
    public let response: LanguageModelV3StreamResponseInfo?

    public init(
        stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        request: LanguageModelV3RequestInfo? = nil,
        response: LanguageModelV3StreamResponseInfo? = nil
    ) {
        self.stream = stream
        self.request = request
        self.response = response
    }
}

/// Request information for telemetry
public struct LanguageModelV3RequestInfo: Sendable {
    /// Request HTTP body that was sent to the provider API.
    public let body: JSONValue?

    public init(body: JSONValue? = nil) {
        self.body = body
    }
}

/// Response information for non-streaming calls
/// This is an intersection type in TypeScript: LanguageModelV3ResponseMetadata & { headers?, body? }
/// In Swift, we flatten all fields to one level.
public struct LanguageModelV3ResponseInfo: Sendable {
    // Fields from LanguageModelV3ResponseMetadata:

    /// ID for the generated response, if the provider sends one.
    public let id: String?

    /// Timestamp for the start of the generated response, if the provider sends one.
    public let timestamp: Date?

    /// The ID of the response model that was used to generate the response, if the provider sends one.
    public let modelId: String?

    // Additional fields:

    /// Response headers.
    public let headers: SharedV3Headers?

    /// Response HTTP body.
    public let body: JSONValue?

    public init(
        id: String? = nil,
        timestamp: Date? = nil,
        modelId: String? = nil,
        headers: SharedV3Headers? = nil,
        body: JSONValue? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}

/// Response information for streaming calls
/// In TypeScript: { headers?: SharedV3Headers }
/// Note: Unlike ResponseInfo, stream response does NOT include metadata fields.
public struct LanguageModelV3StreamResponseInfo: Sendable {
    /// Response headers.
    public let headers: SharedV3Headers?

    public init(headers: SharedV3Headers? = nil) {
        self.headers = headers
    }
}

