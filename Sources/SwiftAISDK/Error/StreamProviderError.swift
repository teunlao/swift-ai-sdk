import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error reported by a provider after a model response stream has started.

 Port of `@ai-sdk/ai/src/error/stream-provider-error.ts`.
 */
public struct StreamProviderError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_StreamProviderError"

    public let name = "AI_StreamProviderError"
    public let message: String
    public let cause: (any Error)?

    /// Provider-defined error type, when supplied by the provider.
    public let type: String?

    /// Provider-defined error code, when supplied by the provider.
    public let code: ProviderStreamError.Code?

    /// HTTP-equivalent status code, when supplied by or inferable from the provider error metadata.
    public let statusCode: Int?

    /// Whether retrying the model call may succeed.
    public let isRetryable: Bool

    /// Original provider error payload.
    public let data: JSONValue?

    public init(
        message: String,
        type: String? = nil,
        code: ProviderStreamError.Code? = nil,
        statusCode: Int? = nil,
        isRetryable: Bool? = nil,
        data: JSONValue? = nil,
        cause: (any Error)? = nil
    ) {
        self.message = message
        self.type = type
        self.code = code
        self.statusCode = statusCode
        self.isRetryable = isRetryable ?? isRetryableStreamStatusCode(statusCode)
        self.data = data
        self.cause = cause
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

func isRetryableStreamStatusCode(_ statusCode: Int?) -> Bool {
    guard let statusCode else { return false }
    return statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
}
