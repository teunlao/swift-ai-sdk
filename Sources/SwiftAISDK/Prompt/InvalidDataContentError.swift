import Foundation
import AISDKProvider

/**
 * Invalid data content error.
 *
 * Port of `@ai-sdk/ai/src/prompt/invalid-data-content-error.ts`.
 */
public struct InvalidDataContentError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidDataContentError"

    public let name = "AI_InvalidDataContentError"
    public let message: String
    public let cause: (any Error)?
    public let content: Any

    public init(
        content: Any,
        message: String? = nil,
        cause: (any Error)? = nil
    ) {
        self.content = content
        self.cause = cause
        if let message {
            self.message = message
        } else {
            self.message = "Invalid data content. Expected a base64 string or binary payload, but got \(Self.describeType(of: content))."
        }
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }

    private static func describeType(of value: Any) -> String {
        if let value = value as? Any.Type {
            return String(reflecting: value)
        }
        return String(reflecting: type(of: value))
    }
}
