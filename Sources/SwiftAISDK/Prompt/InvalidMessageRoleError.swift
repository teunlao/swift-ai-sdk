import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when an invalid message role is encountered.

 Port of `@ai-sdk/ai/src/prompt/invalid-message-role-error.ts`.
 */
public struct InvalidMessageRoleError: Error, Sendable, Equatable {
    /// The invalid role that was encountered.
    public let role: String

    /// Error message.
    public let message: String

    public init(role: String, message: String? = nil) {
        self.role = role
        self.message = message ?? "Invalid message role: '\(role)'. Must be one of: \"system\", \"user\", \"assistant\", \"tool\"."
    }
}

extension InvalidMessageRoleError: CustomStringConvertible {
    public var description: String {
        "AI_InvalidMessageRoleError: \(message)"
    }
}

extension InvalidMessageRoleError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
