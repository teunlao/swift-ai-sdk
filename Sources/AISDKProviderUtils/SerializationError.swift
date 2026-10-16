import Foundation
import AISDKProvider

/**
 A value could not be serialized.

 Port of `@ai-sdk/provider-utils/src/serialization-error.ts`.
 */
public struct SerializationError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_SerializationError"

    public let name = "AI_SerializationError"
    public let message: String
    public let cause: (any Error)?

    public init(message: String = "Failed to serialize value.", cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
